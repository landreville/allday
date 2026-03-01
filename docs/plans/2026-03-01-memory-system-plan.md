# Memory System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build All-Day's memory API — a Rails 8 API that ingests Claude Code JSONL transcripts, breaks them into topic-based summary chunks via LLM, and makes them semantically searchable via pgvector.

**Architecture:** Monolithic Rails 8 API-only app. PostgreSQL + pgvector for storage and vector search. Sidekiq + Redis for async summarization. Anthropic Ruby SDK for LLM summarization. The `neighbor` gem for pgvector integration. API key auth.

**Tech Stack:** Ruby 3.4, Rails 8, PostgreSQL 17, pgvector, Redis, Sidekiq, neighbor gem, anthropic-sdk-ruby, RSpec

**Design doc:** `docs/plans/2026-03-01-memory-system-design.md`

---

### Task 1: Rails Project Scaffold

**Files:**
- Create: `Gemfile`, `config/`, `app/`, etc. (via `rails new`)
- Modify: `Gemfile` (add gems)
- Modify: `config/database.yml`

**Step 1: Generate Rails API-only app**

Run in the project root (which already has `.git`):
```bash
rails new . --api --database=postgresql --skip-git --skip-docker --skip-action-mailer --skip-action-mailbox --skip-action-text --skip-active-storage --skip-action-cable --skip-javascript --skip-asset-pipeline --skip-hotwire --force
```

The `--skip-git` flag preserves our existing git repo. `--force` overwrites the existing `.gitignore`.

**Step 2: Add required gems to Gemfile**

Add these gems to the `Gemfile`:
```ruby
# Vector search
gem "neighbor"

# Background jobs
gem "sidekiq"

# Anthropic API
gem "anthropic-sdk-ruby"

# HTTP client for embedding APIs
gem "faraday"
```

Add to the test/development group:
```ruby
group :development, :test do
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "webmock"
  gem "shoulda-matchers"
end
```

**Step 3: Bundle install**

Run: `bundle install`

**Step 4: Install RSpec**

Run: `rails generate rspec:install`

**Step 5: Configure shoulda-matchers**

Add to `spec/rails_helper.rb` at the bottom (inside the existing file, before the final `end` if there is one, or at the bottom):

```ruby
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
```

**Step 6: Configure database.yml**

Ensure `config/database.yml` has the right database names. The defaults from `rails new` should work (allday_development, allday_test). If PostgreSQL requires a specific user/password, configure that too. The default should use the local socket.

**Step 7: Create databases and generate neighbor pgvector migration**

Run:
```bash
rails db:create
rails generate neighbor:vector
rails db:migrate
```

This creates the pgvector extension in the database.

**Step 8: Commit**

```bash
git add -A
git commit -m "feat: scaffold Rails 8 API with pgvector, Sidekiq, and RSpec"
```

---

### Task 2: User Model and Migration

**Files:**
- Create: `db/migrate/TIMESTAMP_create_users.rb`
- Create: `app/models/user.rb`
- Create: `spec/models/user_spec.rb`
- Create: `spec/factories/users.rb`

**Step 1: Write the failing test**

Create `spec/models/user_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe User, type: :model do
  subject { build(:user) }

  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
    it { should validate_presence_of(:api_key) }
    it { should validate_uniqueness_of(:api_key) }
  end

  describe "associations" do
    it { should have_many(:agents).dependent(:destroy) }
  end

  describe "#generate_api_key" do
    it "generates a unique api_key before validation if blank" do
      user = User.new(name: "Test", email: "test@example.com")
      user.valid?
      expect(user.api_key).to be_present
      expect(user.api_key.length).to be >= 32
    end
  end
end
```

Create `spec/factories/users.rb`:
```ruby
FactoryBot.define do
  factory :user do
    name { "Test User" }
    sequence(:email) { |n| "user#{n}@example.com" }
    api_key { SecureRandom.hex(32) }
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/user_spec.rb`
Expected: FAIL — User model doesn't exist yet.

**Step 3: Generate migration and model**

Run: `rails generate model User name:string email:string api_key:string --no-fixture`

Edit the generated migration to add indexes and constraints:
```ruby
class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :api_key, null: false

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :api_key, unique: true
  end
end
```

Edit `app/models/user.rb`:
```ruby
class User < ApplicationRecord
  has_many :agents, dependent: :destroy

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :api_key, presence: true, uniqueness: true

  before_validation :generate_api_key, on: :create

  private

  def generate_api_key
    self.api_key = SecureRandom.hex(32) if api_key.blank?
  end
end
```

**Step 4: Run migration and test**

Run: `rails db:migrate && bundle exec rspec spec/models/user_spec.rb`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add User model with API key generation"
```

---

### Task 3: Agent Model and Migration

**Files:**
- Create: `db/migrate/TIMESTAMP_create_agents.rb`
- Create: `app/models/agent.rb`
- Create: `spec/models/agent_spec.rb`
- Create: `spec/factories/agents.rb`

**Step 1: Write the failing test**

Create `spec/models/agent_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Agent, type: :model do
  subject { build(:agent) }

  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:origin) }
    it { should define_enum_for(:origin).with_values(blank_slate: 0, continued: 1, branched: 2) }
  end

  describe "associations" do
    it { should belong_to(:user) }
    it { should belong_to(:parent).class_name("Agent").optional }
    it { should have_many(:children).class_name("Agent").with_foreign_key(:parent_id) }
    it { should have_many(:transcripts).dependent(:destroy) }
    it { should have_many(:memory_chunks).dependent(:destroy) }
  end

  describe "branching" do
    it "requires parent when origin is branched" do
      agent = build(:agent, origin: :branched, parent: nil)
      expect(agent).not_to be_valid
      expect(agent.errors[:parent_id]).to include("is required for branched agents")
    end

    it "does not require parent for blank_slate" do
      agent = build(:agent, origin: :blank_slate, parent: nil)
      expect(agent).to be_valid
    end
  end
end
```

Create `spec/factories/agents.rb`:
```ruby
FactoryBot.define do
  factory :agent do
    user
    sequence(:name) { |n| "agent-#{n}" }
    model_name { "claude-sonnet-4-6" }
    origin { :blank_slate }
    model_config { {} }
    metadata { {} }
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/agent_spec.rb`
Expected: FAIL — Agent model doesn't exist.

**Step 3: Generate migration and model**

Run: `rails generate model Agent user:references name:string model_name:string model_config:jsonb parent_id:bigint origin:integer metadata:jsonb --no-fixture`

Edit the migration:
```ruby
class CreateAgents < ActiveRecord::Migration[8.0]
  def change
    create_table :agents do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :model_name
      t.jsonb :model_config, default: {}
      t.bigint :parent_id
      t.integer :origin, default: 0, null: false
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_foreign_key :agents, :agents, column: :parent_id
    add_index :agents, :parent_id
  end
end
```

Edit `app/models/agent.rb`:
```ruby
class Agent < ApplicationRecord
  belongs_to :user
  belongs_to :parent, class_name: "Agent", optional: true
  has_many :children, class_name: "Agent", foreign_key: :parent_id, dependent: :nullify
  has_many :transcripts, dependent: :destroy
  has_many :memory_chunks, dependent: :destroy

  enum :origin, { blank_slate: 0, continued: 1, branched: 2 }

  validates :name, presence: true
  validates :origin, presence: true
  validate :parent_required_for_branched

  private

  def parent_required_for_branched
    if branched? && parent_id.blank?
      errors.add(:parent_id, "is required for branched agents")
    end
  end
end
```

**Step 4: Run migration and tests**

Run: `rails db:migrate && bundle exec rspec spec/models/agent_spec.rb`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Agent model with lineage tracking"
```

---

### Task 4: Transcript Model and Migration

**Files:**
- Create: `db/migrate/TIMESTAMP_create_transcripts.rb`
- Create: `app/models/transcript.rb`
- Create: `spec/models/transcript_spec.rb`
- Create: `spec/factories/transcripts.rb`

**Step 1: Write the failing test**

Create `spec/models/transcript_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Transcript, type: :model do
  subject { build(:transcript) }

  describe "validations" do
    it { should validate_presence_of(:source) }
    it { should validate_presence_of(:status) }
    it { should define_enum_for(:status).with_values(active: 0, completed: 1) }
  end

  describe "associations" do
    it { should belong_to(:agent) }
    it { should have_many(:messages).dependent(:destroy) }
    it { should have_many(:memory_chunks).dependent(:destroy) }
  end
end
```

Create `spec/factories/transcripts.rb`:
```ruby
FactoryBot.define do
  factory :transcript do
    agent
    source { "claude-code" }
    source_session_id { SecureRandom.uuid }
    status { :active }
    started_at { Time.current }
    metadata { {} }
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/transcript_spec.rb`
Expected: FAIL.

**Step 3: Generate migration and model**

Run: `rails generate model Transcript agent:references source:string source_session_id:string status:integer started_at:datetime completed_at:datetime metadata:jsonb --no-fixture`

Edit the migration:
```ruby
class CreateTranscripts < ActiveRecord::Migration[8.0]
  def change
    create_table :transcripts do |t|
      t.references :agent, null: false, foreign_key: true
      t.string :source, null: false
      t.string :source_session_id
      t.integer :status, default: 0, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :transcripts, :source_session_id
  end
end
```

Edit `app/models/transcript.rb`:
```ruby
class Transcript < ApplicationRecord
  belongs_to :agent
  has_many :messages, dependent: :destroy
  has_many :memory_chunks, dependent: :destroy

  enum :status, { active: 0, completed: 1 }

  validates :source, presence: true
  validates :status, presence: true
end
```

**Step 4: Run migration and tests**

Run: `rails db:migrate && bundle exec rspec spec/models/transcript_spec.rb`
Expected: PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Transcript model"
```

---

### Task 5: Message Model and Migration

**Files:**
- Create: `db/migrate/TIMESTAMP_create_messages.rb`
- Create: `app/models/message.rb`
- Create: `spec/models/message_spec.rb`
- Create: `spec/factories/messages.rb`

**Step 1: Write the failing test**

Create `spec/models/message_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Message, type: :model do
  subject { build(:message) }

  describe "validations" do
    it { should validate_presence_of(:role) }
    it { should validate_presence_of(:sequence) }
    it { should define_enum_for(:role).with_values(user: 0, assistant: 1, system: 2, tool_call: 3, tool_result: 4) }
  end

  describe "associations" do
    it { should belong_to(:transcript) }
    it { should belong_to(:agent) }
  end

  describe "ordering" do
    it "has a default scope ordered by sequence" do
      transcript = create(:transcript)
      msg3 = create(:message, transcript: transcript, agent: transcript.agent, sequence: 3)
      msg1 = create(:message, transcript: transcript, agent: transcript.agent, sequence: 1)
      msg2 = create(:message, transcript: transcript, agent: transcript.agent, sequence: 2)

      expect(transcript.messages).to eq([msg1, msg2, msg3])
    end
  end
end
```

Create `spec/factories/messages.rb`:
```ruby
FactoryBot.define do
  factory :message do
    transcript
    agent { transcript.agent }
    role { :user }
    content { "Hello" }
    sequence(:sequence) { |n| n }
    timestamp { Time.current }
    metadata { {} }
  end
end
```

Note: The `sequence` field uses FactoryBot's `sequence` method which auto-increments. The field name happens to also be `sequence`. This is fine — FactoryBot distinguishes them.

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/message_spec.rb`
Expected: FAIL.

**Step 3: Generate migration and model**

Run: `rails generate model Message transcript:references agent:references role:integer content:text thinking:text sequence:integer timestamp:datetime metadata:jsonb --no-fixture`

Edit the migration:
```ruby
class CreateMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :messages do |t|
      t.references :transcript, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: true
      t.integer :role, null: false
      t.text :content
      t.text :thinking
      t.integer :sequence, null: false
      t.datetime :timestamp
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :messages, [:transcript_id, :sequence], unique: true
  end
end
```

Edit `app/models/message.rb`:
```ruby
class Message < ApplicationRecord
  belongs_to :transcript
  belongs_to :agent

  enum :role, { user: 0, assistant: 1, system: 2, tool_call: 3, tool_result: 4 }

  validates :role, presence: true
  validates :sequence, presence: true

  default_scope { order(:sequence) }
end
```

**Step 4: Run migration and tests**

Run: `rails db:migrate && bundle exec rspec spec/models/message_spec.rb`
Expected: PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Message model with sequence ordering"
```

---

### Task 6: MemoryChunk Model and Migration (with pgvector)

**Files:**
- Create: `db/migrate/TIMESTAMP_create_memory_chunks.rb`
- Create: `app/models/memory_chunk.rb`
- Create: `spec/models/memory_chunk_spec.rb`
- Create: `spec/factories/memory_chunks.rb`

**Step 1: Write the failing test**

Create `spec/models/memory_chunk_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe MemoryChunk, type: :model do
  subject { build(:memory_chunk) }

  describe "validations" do
    it { should validate_presence_of(:topic) }
    it { should validate_presence_of(:summary) }
  end

  describe "associations" do
    it { should belong_to(:transcript) }
    it { should belong_to(:agent) }
  end

  describe "vector search" do
    it "finds nearest neighbors by embedding" do
      agent = create(:agent)
      transcript = create(:transcript, agent: agent)

      # Create chunks with known embeddings (1536 dims is typical, use 3 for test)
      chunk1 = create(:memory_chunk, transcript: transcript, agent: agent,
        topic: "auth", embedding: [1.0, 0.0, 0.0])
      chunk2 = create(:memory_chunk, transcript: transcript, agent: agent,
        topic: "database", embedding: [0.0, 1.0, 0.0])

      results = MemoryChunk.nearest_neighbors(:embedding, [1.0, 0.1, 0.0], distance: "cosine").first(5)
      expect(results.first).to eq(chunk1)
    end
  end
end
```

Create `spec/factories/memory_chunks.rb`:
```ruby
FactoryBot.define do
  factory :memory_chunk do
    transcript
    agent { transcript.agent }
    topic { "implemented feature" }
    summary { "Did some work on a feature." }
    embedding { Array.new(3) { rand(-1.0..1.0) } }
    skills_demonstrated { ["ruby", "testing"] }
    message_range_start { 1 }
    message_range_end { 10 }
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/memory_chunk_spec.rb`
Expected: FAIL.

**Step 3: Generate migration and model**

Run: `rails generate model MemoryChunk transcript:references agent:references topic:string summary:text skills_demonstrated:text message_range_start:integer message_range_end:integer --no-fixture`

Edit the migration (add the vector column and index manually):
```ruby
class CreateMemoryChunks < ActiveRecord::Migration[8.0]
  def change
    create_table :memory_chunks do |t|
      t.references :transcript, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: true
      t.string :topic, null: false
      t.text :summary, null: false
      t.column :embedding, :vector, limit: 1536
      t.text :skills_demonstrated, array: true, default: []
      t.integer :message_range_start
      t.integer :message_range_end

      t.timestamps
    end

    add_index :memory_chunks, :embedding, using: :hnsw, opclass: :vector_cosine_ops
  end
end
```

Note: We use 1536 dimensions (matching common embedding model output sizes). The HNSW index with `vector_cosine_ops` enables fast cosine similarity search. For tests, we use 3-dimensional vectors — pgvector handles mismatched dimensions gracefully for queries, but for the test factory we need to match the column dimension or use a test-specific dimension. Actually, pgvector requires the dimensions to match the column definition. So either:
- Use 1536-dim vectors in tests (pad with zeros), or
- Set the test column to a smaller dimension.

For simplicity, update the test factory to use 1536-dim vectors:

Update `spec/factories/memory_chunks.rb`:
```ruby
FactoryBot.define do
  factory :memory_chunk do
    transcript
    agent { transcript.agent }
    topic { "implemented feature" }
    summary { "Did some work on a feature." }
    embedding { Array.new(1536) { rand(-1.0..1.0) } }
    skills_demonstrated { ["ruby", "testing"] }
    message_range_start { 1 }
    message_range_end { 10 }
  end
end
```

Update the test to use 1536-dim vectors too:
```ruby
chunk1 = create(:memory_chunk, transcript: transcript, agent: agent,
  topic: "auth", embedding: [1.0] + Array.new(1535, 0.0))
chunk2 = create(:memory_chunk, transcript: transcript, agent: agent,
  topic: "database", embedding: [0.0, 1.0] + Array.new(1534, 0.0))

results = MemoryChunk.nearest_neighbors(:embedding, [1.0, 0.1] + Array.new(1534, 0.0), distance: "cosine").first(5)
```

Edit `app/models/memory_chunk.rb`:
```ruby
class MemoryChunk < ApplicationRecord
  belongs_to :transcript
  belongs_to :agent

  has_neighbors :embedding

  validates :topic, presence: true
  validates :summary, presence: true
end
```

**Step 4: Run migration and tests**

Run: `rails db:migrate && bundle exec rspec spec/models/memory_chunk_spec.rb`
Expected: PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add MemoryChunk model with pgvector search"
```

---

### Task 7: API Authentication

**Files:**
- Create: `app/controllers/api/v1/base_controller.rb`
- Create: `spec/support/auth_helpers.rb`
- Create: `spec/requests/api/v1/authentication_spec.rb`

**Step 1: Write the failing test**

Create `spec/support/auth_helpers.rb`:
```ruby
module AuthHelpers
  def auth_headers(user, agent: nil)
    headers = { "Authorization" => "Bearer #{user.api_key}" }
    headers["X-Agent-Id"] = agent.id.to_s if agent
    headers
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
```

Make sure `spec/rails_helper.rb` loads support files. Add this line (it may be commented out already):
```ruby
Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }
```

Create `spec/requests/api/v1/authentication_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "API Authentication", type: :request do
  describe "without authentication" do
    it "returns 401" do
      get "/api/v1/agents"
      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("Invalid API key")
    end
  end

  describe "with valid API key" do
    it "returns 200" do
      user = create(:user)
      get "/api/v1/agents", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "with invalid API key" do
    it "returns 401" do
      get "/api/v1/agents", headers: { "Authorization" => "Bearer bad-key" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/api/v1/authentication_spec.rb`
Expected: FAIL — routes and controller don't exist.

**Step 3: Implement authentication**

Create `app/controllers/api/v1/base_controller.rb`:
```ruby
module Api
  module V1
    class BaseController < ApplicationController
      before_action :authenticate!

      private

      def authenticate!
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")
        @current_user = User.find_by(api_key: token)

        unless @current_user
          render json: { error: "Invalid API key" }, status: :unauthorized
        end
      end

      def current_user
        @current_user
      end

      def current_agent
        @current_agent ||= if request.headers["X-Agent-Id"].present?
          current_user.agents.find_by(id: request.headers["X-Agent-Id"])
        end
      end
    end
  end
end
```

We need a placeholder agents route for the auth test. Create `app/controllers/api/v1/agents_controller.rb` (minimal, will be expanded in Task 8):
```ruby
module Api
  module V1
    class AgentsController < BaseController
      def index
        agents = current_user.agents
        render json: agents
      end
    end
  end
end
```

Add routes to `config/routes.rb`:
```ruby
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :agents, only: [:index]
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/requests/api/v1/authentication_spec.rb`
Expected: PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add API key authentication"
```

---

### Task 8: Agents API (CRUD)

**Files:**
- Modify: `app/controllers/api/v1/agents_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/api/v1/agents_spec.rb`

**Step 1: Write the failing tests**

Create `spec/requests/api/v1/agents_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Api::V1::Agents", type: :request do
  let(:user) { create(:user) }

  describe "GET /api/v1/agents" do
    it "lists the user's agents" do
      create(:agent, user: user, name: "agent-1")
      create(:agent, user: user, name: "agent-2")
      create(:agent) # another user's agent

      get "/api/v1/agents", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(2)
      expect(body.map { |a| a["name"] }).to contain_exactly("agent-1", "agent-2")
    end
  end

  describe "POST /api/v1/agents" do
    it "creates a blank_slate agent" do
      post "/api/v1/agents", headers: auth_headers(user), params: {
        agent: { name: "my-agent", model_name: "claude-opus-4-6", origin: "blank_slate" }
      }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["name"]).to eq("my-agent")
      expect(body["origin"]).to eq("blank_slate")
      expect(body["user_id"]).to eq(user.id)
    end

    it "creates a branched agent" do
      parent = create(:agent, user: user)
      post "/api/v1/agents", headers: auth_headers(user), params: {
        agent: { name: "child-agent", origin: "branched", parent_id: parent.id }
      }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["parent_id"]).to eq(parent.id)
    end

    it "returns 422 for invalid params" do
      post "/api/v1/agents", headers: auth_headers(user), params: {
        agent: { name: "" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/agents/:id" do
    it "returns the agent with lineage info" do
      parent = create(:agent, user: user, name: "parent")
      child = create(:agent, user: user, name: "child", origin: :branched, parent: parent)

      get "/api/v1/agents/#{child.id}", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["name"]).to eq("child")
      expect(body["parent_id"]).to eq(parent.id)
    end

    it "returns 404 for another user's agent" do
      other_agent = create(:agent)
      get "/api/v1/agents/#{other_agent.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/agents/:id/memories" do
    it "returns the agent's memory chunks" do
      agent = create(:agent, user: user)
      transcript = create(:transcript, agent: agent)
      create(:memory_chunk, agent: agent, transcript: transcript, topic: "auth work")

      get "/api/v1/agents/#{agent.id}/memories", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["topic"]).to eq("auth work")
    end
  end

  describe "GET /api/v1/agents/:id/transcripts" do
    it "returns the agent's transcripts" do
      agent = create(:agent, user: user)
      create(:transcript, agent: agent, source: "claude-code")

      get "/api/v1/agents/#{agent.id}/transcripts", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["source"]).to eq("claude-code")
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/requests/api/v1/agents_spec.rb`
Expected: FAIL — missing routes and controller actions.

**Step 3: Implement controller and routes**

Update `config/routes.rb`:
```ruby
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :agents, only: [:index, :show, :create] do
        member do
          get :memories
          get :transcripts
        end
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
```

Update `app/controllers/api/v1/agents_controller.rb`:
```ruby
module Api
  module V1
    class AgentsController < BaseController
      def index
        agents = current_user.agents
        render json: agents
      end

      def show
        agent = current_user.agents.find_by(id: params[:id])
        if agent
          render json: agent
        else
          render json: { error: "Not found" }, status: :not_found
        end
      end

      def create
        agent = current_user.agents.build(agent_params)
        if agent.save
          render json: agent, status: :created
        else
          render json: { errors: agent.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def memories
        agent = current_user.agents.find_by(id: params[:id])
        return render json: { error: "Not found" }, status: :not_found unless agent

        chunks = agent.memory_chunks.select(:id, :topic, :summary, :skills_demonstrated,
          :transcript_id, :message_range_start, :message_range_end, :created_at)
        render json: chunks
      end

      def transcripts
        agent = current_user.agents.find_by(id: params[:id])
        return render json: { error: "Not found" }, status: :not_found unless agent

        render json: agent.transcripts
      end

      private

      def agent_params
        params.require(:agent).permit(:name, :model_name, :origin, :parent_id, model_config: {}, metadata: {})
      end
    end
  end
end
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/requests/api/v1/agents_spec.rb`
Expected: PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Agents API with CRUD and memory/transcript endpoints"
```

---

### Task 9: Transcripts API (Create, Update, Show)

**Files:**
- Create: `app/controllers/api/v1/transcripts_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/api/v1/transcripts_spec.rb`

**Step 1: Write the failing tests**

Create `spec/requests/api/v1/transcripts_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Api::V1::Transcripts", type: :request do
  let(:user) { create(:user) }
  let(:agent) { create(:agent, user: user) }

  describe "POST /api/v1/transcripts" do
    it "creates a new active transcript" do
      post "/api/v1/transcripts", headers: auth_headers(user), params: {
        transcript: { agent_id: agent.id, source: "claude-code", source_session_id: "abc-123" }
      }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("active")
      expect(body["source"]).to eq("claude-code")
      expect(body["agent_id"]).to eq(agent.id)
    end

    it "rejects transcript for another user's agent" do
      other_agent = create(:agent)
      post "/api/v1/transcripts", headers: auth_headers(user), params: {
        transcript: { agent_id: other_agent.id, source: "claude-code" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/transcripts/:id" do
    it "returns transcript metadata" do
      transcript = create(:transcript, agent: agent)

      get "/api/v1/transcripts/#{transcript.id}", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(transcript.id)
    end
  end

  describe "PATCH /api/v1/transcripts/:id" do
    it "marks transcript as completed" do
      transcript = create(:transcript, agent: agent, status: :active)

      patch "/api/v1/transcripts/#{transcript.id}", headers: auth_headers(user), params: {
        transcript: { status: "completed" }
      }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("completed")
      expect(body["completed_at"]).to be_present
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/requests/api/v1/transcripts_spec.rb`
Expected: FAIL.

**Step 3: Implement controller and routes**

Update `config/routes.rb` — add transcripts:
```ruby
resources :transcripts, only: [:show, :create, :update]
```

Create `app/controllers/api/v1/transcripts_controller.rb`:
```ruby
module Api
  module V1
    class TranscriptsController < BaseController
      def show
        transcript = find_transcript
        return render json: { error: "Not found" }, status: :not_found unless transcript

        render json: transcript
      end

      def create
        agent = current_user.agents.find_by(id: transcript_params[:agent_id])
        unless agent
          return render json: { errors: ["Agent not found or not owned by you"] }, status: :unprocessable_entity
        end

        transcript = agent.transcripts.build(transcript_params.merge(started_at: Time.current))
        if transcript.save
          render json: transcript, status: :created
        else
          render json: { errors: transcript.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        transcript = find_transcript
        return render json: { error: "Not found" }, status: :not_found unless transcript

        attrs = transcript_params
        if attrs[:status] == "completed" && transcript.active?
          attrs[:completed_at] = Time.current
        end

        if transcript.update(attrs)
          SummarizeTranscriptJob.perform_later(transcript.id) if transcript.completed?
          render json: transcript
        else
          render json: { errors: transcript.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def find_transcript
        Transcript.joins(:agent).where(agents: { user_id: current_user.id }).find_by(id: params[:id])
      end

      def transcript_params
        params.require(:transcript).permit(:agent_id, :source, :source_session_id, :status, metadata: {})
      end
    end
  end
end
```

Note: The `SummarizeTranscriptJob` doesn't exist yet — that's Task 13. For now, create a placeholder so the controller doesn't error. Create `app/jobs/summarize_transcript_job.rb`:
```ruby
class SummarizeTranscriptJob < ApplicationJob
  queue_as :default

  def perform(transcript_id)
    # TODO: implement in Task 13
  end
end
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/requests/api/v1/transcripts_spec.rb`
Expected: PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Transcripts API with create, show, update"
```

---

### Task 10: Messages API (Create, Index)

**Files:**
- Create: `app/controllers/api/v1/messages_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/api/v1/messages_spec.rb`

**Step 1: Write the failing tests**

Create `spec/requests/api/v1/messages_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Api::V1::Messages", type: :request do
  let(:user) { create(:user) }
  let(:agent) { create(:agent, user: user) }
  let(:transcript) { create(:transcript, agent: agent, status: :active) }

  describe "POST /api/v1/transcripts/:transcript_id/messages" do
    it "appends a message to the transcript" do
      post "/api/v1/transcripts/#{transcript.id}/messages", headers: auth_headers(user), params: {
        message: { role: "user", content: "Hello there", sequence: 1 }
      }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["role"]).to eq("user")
      expect(body["content"]).to eq("Hello there")
      expect(body["sequence"]).to eq(1)
    end

    it "appends an assistant message with thinking" do
      post "/api/v1/transcripts/#{transcript.id}/messages", headers: auth_headers(user), params: {
        message: { role: "assistant", content: "Hi!", thinking: "User said hello, I should respond.", sequence: 2 }
      }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["thinking"]).to eq("User said hello, I should respond.")
    end

    it "rejects messages on completed transcripts" do
      transcript.update!(status: :completed, completed_at: Time.current)

      post "/api/v1/transcripts/#{transcript.id}/messages", headers: auth_headers(user), params: {
        message: { role: "user", content: "Too late", sequence: 1 }
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/transcripts/:transcript_id/messages" do
    it "returns messages ordered by sequence" do
      create(:message, transcript: transcript, agent: agent, role: :assistant, content: "Second", sequence: 2)
      create(:message, transcript: transcript, agent: agent, role: :user, content: "First", sequence: 1)

      get "/api/v1/transcripts/#{transcript.id}/messages", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.map { |m| m["content"] }).to eq(["First", "Second"])
    end

    it "paginates results" do
      25.times do |i|
        create(:message, transcript: transcript, agent: agent, sequence: i + 1, content: "msg #{i + 1}")
      end

      get "/api/v1/transcripts/#{transcript.id}/messages", headers: auth_headers(user), params: { page: 1, per_page: 10 }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(10)
      expect(body.first["content"]).to eq("msg 1")
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/requests/api/v1/messages_spec.rb`
Expected: FAIL.

**Step 3: Implement controller and routes**

Update `config/routes.rb` — nest messages under transcripts:
```ruby
resources :transcripts, only: [:show, :create, :update] do
  resources :messages, only: [:index, :create]
end
```

Create `app/controllers/api/v1/messages_controller.rb`:
```ruby
module Api
  module V1
    class MessagesController < BaseController
      def index
        transcript = find_transcript
        return render json: { error: "Not found" }, status: :not_found unless transcript

        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 50).to_i.clamp(1, 100)

        messages = transcript.messages.offset((page - 1) * per_page).limit(per_page)
        render json: messages
      end

      def create
        transcript = find_transcript
        return render json: { error: "Not found" }, status: :not_found unless transcript

        unless transcript.active?
          return render json: { errors: ["Cannot add messages to a completed transcript"] }, status: :unprocessable_entity
        end

        message = transcript.messages.build(message_params.merge(agent_id: transcript.agent_id))
        if message.save
          render json: message, status: :created
        else
          render json: { errors: message.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def find_transcript
        Transcript.joins(:agent).where(agents: { user_id: current_user.id }).find_by(id: params[:transcript_id])
      end

      def message_params
        params.require(:message).permit(:role, :content, :thinking, :sequence, :timestamp, metadata: {})
      end
    end
  end
end
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/requests/api/v1/messages_spec.rb`
Expected: PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Messages API with streaming ingestion and pagination"
```

---

### Task 11: JSONL Transcript Import Service

**Files:**
- Create: `app/services/transcript_importer.rb`
- Create: `spec/services/transcript_importer_spec.rb`
- Create: `spec/fixtures/files/sample_transcript.jsonl` (test fixture)

**Step 1: Create a test fixture**

Create `spec/fixtures/files/sample_transcript.jsonl` with realistic Claude Code JSONL content:
```jsonl
{"type":"user","message":{"role":"user","content":"Help me fix the login bug"},"sessionId":"test-session-1","timestamp":"2026-03-01T10:00:00.000Z","uuid":"msg-1","parentUuid":null}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"Let me look at the login code"},{"type":"text","text":"I'll check the auth controller."}],"model":"claude-sonnet-4-6"},"sessionId":"test-session-1","timestamp":"2026-03-01T10:00:05.000Z","uuid":"msg-2","parentUuid":"msg-1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","id":"tool-1","input":{"file_path":"/app/auth.rb"}}]},"sessionId":"test-session-1","timestamp":"2026-03-01T10:00:06.000Z","uuid":"msg-3","parentUuid":"msg-2"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool-1","content":"class Auth; end"}]},"sessionId":"test-session-1","timestamp":"2026-03-01T10:00:07.000Z","uuid":"msg-4","parentUuid":"msg-3"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Found the issue. The session token check is missing."}],"model":"claude-sonnet-4-6"},"sessionId":"test-session-1","timestamp":"2026-03-01T10:00:10.000Z","uuid":"msg-5","parentUuid":"msg-4"}
```

**Step 2: Write the failing test**

Create `spec/services/transcript_importer_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe TranscriptImporter do
  let(:user) { create(:user) }
  let(:agent) { create(:agent, user: user) }
  let(:jsonl_path) { Rails.root.join("spec/fixtures/files/sample_transcript.jsonl") }
  let(:jsonl_content) { File.read(jsonl_path) }

  describe "#import" do
    it "creates a transcript with messages from JSONL content" do
      result = described_class.new(
        agent: agent,
        jsonl_content: jsonl_content,
        source: "claude-code",
        source_session_id: "test-session-1"
      ).import

      expect(result).to be_a(Transcript)
      expect(result).to be_persisted
      expect(result.status).to eq("completed")
      expect(result.messages.count).to eq(5)
    end

    it "extracts user messages" do
      result = described_class.new(agent: agent, jsonl_content: jsonl_content, source: "claude-code").import
      user_msgs = result.messages.where(role: :user)
      expect(user_msgs.count).to eq(2)
      expect(user_msgs.first.content).to include("login bug")
    end

    it "extracts assistant messages with thinking" do
      result = described_class.new(agent: agent, jsonl_content: jsonl_content, source: "claude-code").import
      assistant_msgs = result.messages.where(role: :assistant)
      expect(assistant_msgs.first.thinking).to eq("Let me look at the login code")
      expect(assistant_msgs.first.content).to include("auth controller")
    end

    it "extracts tool_call messages" do
      result = described_class.new(agent: agent, jsonl_content: jsonl_content, source: "claude-code").import
      tool_msgs = result.messages.where(role: :tool_call)
      expect(tool_msgs.count).to eq(1)
      expect(tool_msgs.first.metadata).to include("tool_name" => "Read")
    end

    it "extracts tool_result messages" do
      result = described_class.new(agent: agent, jsonl_content: jsonl_content, source: "claude-code").import
      result_msgs = result.messages.where(role: :tool_result)
      expect(result_msgs.count).to eq(1)
    end

    it "assigns sequential sequence numbers" do
      result = described_class.new(agent: agent, jsonl_content: jsonl_content, source: "claude-code").import
      sequences = result.messages.pluck(:sequence)
      expect(sequences).to eq([1, 2, 3, 4, 5])
    end

    it "skips non-message JSONL lines (progress, file-history-snapshot)" do
      content_with_extras = <<~JSONL
        {"type":"progress","data":{"type":"hook_progress"},"timestamp":"2026-03-01T10:00:00.000Z","uuid":"p1"}
        {"type":"user","message":{"role":"user","content":"Hello"},"timestamp":"2026-03-01T10:00:01.000Z","uuid":"u1","parentUuid":"p1"}
        {"type":"file-history-snapshot","messageId":"snap1","snapshot":{}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}],"model":"claude-sonnet-4-6"},"timestamp":"2026-03-01T10:00:02.000Z","uuid":"a1","parentUuid":"u1"}
      JSONL

      result = described_class.new(agent: agent, jsonl_content: content_with_extras, source: "claude-code").import
      expect(result.messages.count).to eq(2)
    end
  end
end
```

**Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/services/transcript_importer_spec.rb`
Expected: FAIL — TranscriptImporter doesn't exist.

**Step 4: Implement the service**

Create `app/services/transcript_importer.rb`:
```ruby
class TranscriptImporter
  def initialize(agent:, jsonl_content:, source:, source_session_id: nil, metadata: {})
    @agent = agent
    @jsonl_content = jsonl_content
    @source = source
    @source_session_id = source_session_id
    @metadata = metadata
  end

  def import
    transcript = @agent.transcripts.create!(
      source: @source,
      source_session_id: @source_session_id,
      status: :completed,
      started_at: nil,
      completed_at: Time.current,
      metadata: @metadata
    )

    sequence = 0
    messages_to_insert = []

    @jsonl_content.each_line do |line|
      line = line.strip
      next if line.empty?

      entry = JSON.parse(line)
      next unless %w[user assistant].include?(entry["type"])

      message_data = entry["message"]
      next unless message_data

      sequence += 1
      parsed = parse_message(message_data, entry)
      next unless parsed

      parsed.each do |msg_attrs|
        messages_to_insert << transcript.messages.build(
          agent_id: @agent.id,
          sequence: sequence,
          timestamp: entry["timestamp"],
          **msg_attrs
        )
        sequence += 1 if msg_attrs != parsed.first # increment for multi-part messages
      end

      # Reset sequence to not double-count if single message
      sequence -= (parsed.length - 1) if parsed.length > 1
      sequence += (parsed.length - 1) if parsed.length > 1
    end

    # Save all messages
    messages_to_insert.each(&:save!)

    # Fix: re-sequence to be clean 1..N
    transcript.messages.unscoped.where(transcript_id: transcript.id).order(:id).each_with_index do |msg, idx|
      msg.update_column(:sequence, idx + 1)
    end

    transcript.reload
    transcript
  end

  private

  def parse_message(message_data, entry)
    role = message_data["role"]
    content = message_data["content"]

    case role
    when "user"
      parse_user_message(content)
    when "assistant"
      parse_assistant_message(content, message_data)
    else
      nil
    end
  end

  def parse_user_message(content)
    if content.is_a?(String)
      [{ role: :user, content: content }]
    elsif content.is_a?(Array)
      # Could be tool_result array
      content.filter_map do |block|
        case block["type"]
        when "tool_result"
          text_content = if block["content"].is_a?(String)
            block["content"]
          elsif block["content"].is_a?(Array)
            block["content"].filter_map { |c| c["text"] }.join("\n")
          end
          { role: :tool_result, content: text_content, metadata: { tool_use_id: block["tool_use_id"] } }
        when "text"
          { role: :user, content: block["text"] }
        end
      end
    end
  end

  def parse_assistant_message(content, message_data)
    if content.is_a?(Array)
      thinking_text = nil
      text_parts = []
      tool_calls = []

      content.each do |block|
        case block["type"]
        when "thinking"
          thinking_text = block["thinking"]
        when "text"
          text_parts << block["text"]
        when "tool_use"
          tool_calls << block
        end
      end

      results = []

      # If we have text (possibly with thinking), make an assistant message
      if text_parts.any?
        results << {
          role: :assistant,
          content: text_parts.join("\n"),
          thinking: thinking_text,
          metadata: { model: message_data["model"] }.compact
        }
      elsif thinking_text && tool_calls.empty?
        # Thinking-only message (no text output)
        results << {
          role: :assistant,
          content: nil,
          thinking: thinking_text,
          metadata: { model: message_data["model"] }.compact
        }
      end

      # Each tool_use becomes a tool_call message
      tool_calls.each do |tc|
        results << {
          role: :tool_call,
          content: tc["input"].to_json,
          thinking: thinking_text && results.empty? ? thinking_text : nil,
          metadata: { tool_name: tc["name"], tool_use_id: tc["id"], model: message_data["model"] }.compact
        }
      end

      results.presence
    elsif content.is_a?(String)
      [{ role: :assistant, content: content }]
    end
  end
end
```

Note: This parser handles the key Claude Code JSONL message types observed in the real data:
- `type: "user"` with string content → user message
- `type: "user"` with array content containing `tool_result` → tool_result message
- `type: "assistant"` with array content containing `thinking`, `text`, `tool_use` blocks → assistant/tool_call messages
- Skips `progress`, `file-history-snapshot`, and other non-message types

**Step 5: Run tests**

Run: `bundle exec rspec spec/services/transcript_importer_spec.rb`
Expected: PASS. If sequence numbering is off, adjust the import logic.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: add TranscriptImporter service for Claude Code JSONL"
```

---

### Task 12: Transcript Import API Endpoint

**Files:**
- Modify: `app/controllers/api/v1/transcripts_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/api/v1/transcripts_import_spec.rb`

**Step 1: Write the failing test**

Create `spec/requests/api/v1/transcripts_import_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Api::V1::Transcripts Import", type: :request do
  let(:user) { create(:user) }
  let(:agent) { create(:agent, user: user) }
  let(:jsonl_content) { File.read(Rails.root.join("spec/fixtures/files/sample_transcript.jsonl")) }

  describe "POST /api/v1/transcripts/import" do
    it "imports a JSONL transcript" do
      post "/api/v1/transcripts/import", headers: auth_headers(user), params: {
        agent_id: agent.id,
        source: "claude-code",
        source_session_id: "session-abc",
        jsonl: jsonl_content
      }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("completed")
      expect(body["message_count"]).to be > 0
    end

    it "returns 422 for invalid agent" do
      post "/api/v1/transcripts/import", headers: auth_headers(user), params: {
        agent_id: 999999,
        source: "claude-code",
        jsonl: jsonl_content
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/api/v1/transcripts_import_spec.rb`
Expected: FAIL — route doesn't exist.

**Step 3: Implement**

Add route to `config/routes.rb` (inside the `api/v1` namespace):
```ruby
post "transcripts/import", to: "transcripts#import"
```

Add `import` action to `app/controllers/api/v1/transcripts_controller.rb`:
```ruby
def import
  agent = current_user.agents.find_by(id: params[:agent_id])
  unless agent
    return render json: { errors: ["Agent not found or not owned by you"] }, status: :unprocessable_entity
  end

  transcript = TranscriptImporter.new(
    agent: agent,
    jsonl_content: params[:jsonl],
    source: params[:source] || "claude-code",
    source_session_id: params[:source_session_id],
    metadata: params[:metadata]&.to_unsafe_h || {}
  ).import

  SummarizeTranscriptJob.perform_later(transcript.id)

  render json: {
    id: transcript.id,
    status: transcript.status,
    message_count: transcript.messages.count,
    agent_id: transcript.agent_id
  }, status: :created
end
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/requests/api/v1/transcripts_import_spec.rb`
Expected: PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add JSONL transcript import endpoint"
```

---

### Task 13: Embedding Service

**Files:**
- Create: `app/services/embedding_service.rb`
- Create: `spec/services/embedding_service_spec.rb`
- Create: `config/initializers/allday.rb`

**Step 1: Write the failing test**

Create `spec/services/embedding_service_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe EmbeddingService do
  describe "#embed" do
    it "returns a vector of floats for a text input" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .with(body: hash_including({ model: "text-embedding-3-small", input: "test text" }))
        .to_return(
          status: 200,
          body: {
            data: [{ embedding: Array.new(1536) { |i| i * 0.001 } }]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = described_class.new.embed("test text")

      expect(result).to be_an(Array)
      expect(result.length).to eq(1536)
      expect(result.first).to be_a(Float)
    end
  end

  describe "#embed_batch" do
    it "returns vectors for multiple texts" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(
          status: 200,
          body: {
            data: [
              { embedding: Array.new(1536) { 0.1 } },
              { embedding: Array.new(1536) { 0.2 } }
            ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      results = described_class.new.embed_batch(["text one", "text two"])

      expect(results.length).to eq(2)
      expect(results.first.length).to eq(1536)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/embedding_service_spec.rb`
Expected: FAIL.

**Step 3: Implement**

Create `config/initializers/allday.rb`:
```ruby
module Allday
  mattr_accessor :embedding_api_key
  mattr_accessor :embedding_model
  mattr_accessor :embedding_dimensions
  mattr_accessor :summarization_model
  mattr_accessor :anthropic_api_key

  self.embedding_api_key = ENV["OPENAI_API_KEY"]
  self.embedding_model = ENV.fetch("EMBEDDING_MODEL", "text-embedding-3-small")
  self.embedding_dimensions = ENV.fetch("EMBEDDING_DIMENSIONS", "1536").to_i
  self.summarization_model = ENV.fetch("SUMMARIZATION_MODEL", "claude-haiku-4-5-20251001")
  self.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
end
```

Create `app/services/embedding_service.rb`:
```ruby
class EmbeddingService
  def initialize
    @conn = Faraday.new(url: "https://api.openai.com") do |f|
      f.request :json
      f.response :json
      f.headers["Authorization"] = "Bearer #{Allday.embedding_api_key}"
    end
  end

  def embed(text)
    embed_batch([text]).first
  end

  def embed_batch(texts)
    response = @conn.post("/v1/embeddings") do |req|
      req.body = {
        model: Allday.embedding_model,
        input: texts
      }
    end

    raise "Embedding API error: #{response.status} #{response.body}" unless response.success?

    response.body["data"].map { |d| d["embedding"] }
  end
end
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/services/embedding_service_spec.rb`
Expected: PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add EmbeddingService for vector generation"
```

---

### Task 14: Summarizer Service

**Files:**
- Create: `app/services/summarizer.rb`
- Create: `spec/services/summarizer_spec.rb`

**Step 1: Write the failing test**

Create `spec/services/summarizer_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Summarizer do
  let(:user) { create(:user) }
  let(:agent) { create(:agent, user: user) }
  let(:transcript) { create(:transcript, agent: agent, status: :completed) }

  before do
    create(:message, transcript: transcript, agent: agent, role: :user, content: "Help me set up OAuth", sequence: 1)
    create(:message, transcript: transcript, agent: agent, role: :assistant, content: "I'll help with OAuth. Let me check the auth controller.", sequence: 2)
    create(:message, transcript: transcript, agent: agent, role: :user, content: "Now let's add rate limiting", sequence: 3)
    create(:message, transcript: transcript, agent: agent, role: :assistant, content: "I'll add rate limiting using Rack::Attack.", sequence: 4)
  end

  describe "#summarize" do
    it "creates memory chunks from transcript messages" do
      llm_response = {
        "chunks" => [
          {
            "topic" => "OAuth setup",
            "summary" => "Helped set up OAuth authentication in the auth controller.",
            "skills" => ["oauth", "authentication", "rails"],
            "message_range_start" => 1,
            "message_range_end" => 2
          },
          {
            "topic" => "Rate limiting",
            "summary" => "Added rate limiting using Rack::Attack middleware.",
            "skills" => ["rate-limiting", "rack", "security"],
            "message_range_start" => 3,
            "message_range_end" => 4
          }
        ]
      }

      # Stub Anthropic API
      anthropic_client = instance_double(Anthropic::Client)
      messages_api = double("messages")
      allow(Anthropic::Client).to receive(:new).and_return(anthropic_client)
      allow(anthropic_client).to receive(:messages).and_return(messages_api)
      allow(messages_api).to receive(:create).and_return(
        double(content: [double(text: llm_response.to_json)])
      )

      # Stub embedding service
      embedding_service = instance_double(EmbeddingService)
      allow(EmbeddingService).to receive(:new).and_return(embedding_service)
      allow(embedding_service).to receive(:embed_batch).and_return([
        Array.new(1536) { 0.1 },
        Array.new(1536) { 0.2 }
      ])

      result = described_class.new(transcript).summarize

      expect(result.length).to eq(2)
      expect(result.first.topic).to eq("OAuth setup")
      expect(result.first.skills_demonstrated).to include("oauth")
      expect(result.first.embedding).to be_present
      expect(result.first.message_range_start).to eq(1)
      expect(result.last.topic).to eq("Rate limiting")
    end

    it "replaces existing memory chunks on re-summarization" do
      # Create an old chunk
      create(:memory_chunk, transcript: transcript, agent: agent, topic: "old topic")

      llm_response = {
        "chunks" => [{
          "topic" => "New topic",
          "summary" => "New summary.",
          "skills" => ["new"],
          "message_range_start" => 1,
          "message_range_end" => 4
        }]
      }

      anthropic_client = instance_double(Anthropic::Client)
      messages_api = double("messages")
      allow(Anthropic::Client).to receive(:new).and_return(anthropic_client)
      allow(anthropic_client).to receive(:messages).and_return(messages_api)
      allow(messages_api).to receive(:create).and_return(
        double(content: [double(text: llm_response.to_json)])
      )

      embedding_service = instance_double(EmbeddingService)
      allow(EmbeddingService).to receive(:new).and_return(embedding_service)
      allow(embedding_service).to receive(:embed_batch).and_return([Array.new(1536) { 0.5 }])

      described_class.new(transcript).summarize

      expect(transcript.memory_chunks.count).to eq(1)
      expect(transcript.memory_chunks.first.topic).to eq("New topic")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/summarizer_spec.rb`
Expected: FAIL.

**Step 3: Implement**

Create `app/services/summarizer.rb`:
```ruby
class Summarizer
  SYSTEM_PROMPT = <<~PROMPT
    You are a conversation analyst. Given a transcript of messages between a user and an AI assistant, identify distinct topics/tasks discussed and produce a JSON summary.

    For each distinct topic, produce:
    - "topic": a short label (3-8 words) describing what was done
    - "summary": 2-3 paragraphs describing what was accomplished, decisions made, problems encountered, and solutions found
    - "skills": an array of skill/technology tags demonstrated (e.g., "postgresql", "debugging", "oauth")
    - "message_range_start": the sequence number of the first message in this topic
    - "message_range_end": the sequence number of the last message in this topic

    Return ONLY valid JSON in this format:
    {
      "chunks": [
        {
          "topic": "...",
          "summary": "...",
          "skills": ["..."],
          "message_range_start": 1,
          "message_range_end": 5
        }
      ]
    }
  PROMPT

  def initialize(transcript)
    @transcript = transcript
  end

  def summarize
    messages = @transcript.messages.select(:role, :content, :thinking, :sequence)
    return [] if messages.empty?

    # Delete existing chunks for idempotency
    @transcript.memory_chunks.destroy_all

    # Build conversation text for LLM
    conversation_text = messages.map do |msg|
      parts = ["[#{msg.sequence}] #{msg.role}:"]
      parts << "(thinking: #{msg.thinking})" if msg.thinking.present?
      parts << msg.content.to_s
      parts.join(" ")
    end.join("\n\n")

    # Call LLM for summarization
    client = Anthropic::Client.new(api_key: Allday.anthropic_api_key)
    response = client.messages.create(
      model: Allday.summarization_model,
      max_tokens: 4096,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: conversation_text }]
    )

    json_text = response.content.find { |c| c.respond_to?(:text) }&.text
    parsed = JSON.parse(json_text)
    chunks_data = parsed["chunks"] || []

    return [] if chunks_data.empty?

    # Generate embeddings for all summaries at once
    summaries = chunks_data.map { |c| "#{c["topic"]}: #{c["summary"]}" }
    embeddings = EmbeddingService.new.embed_batch(summaries)

    # Create memory chunks
    chunks_data.each_with_index.map do |chunk_data, i|
      @transcript.memory_chunks.create!(
        agent_id: @transcript.agent_id,
        topic: chunk_data["topic"],
        summary: chunk_data["summary"],
        embedding: embeddings[i],
        skills_demonstrated: chunk_data["skills"] || [],
        message_range_start: chunk_data["message_range_start"],
        message_range_end: chunk_data["message_range_end"]
      )
    end
  end
end
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/services/summarizer_spec.rb`
Expected: PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Summarizer service with LLM topic extraction and embedding"
```

---

### Task 15: SummarizeTranscriptJob Implementation

**Files:**
- Modify: `app/jobs/summarize_transcript_job.rb`
- Create: `spec/jobs/summarize_transcript_job_spec.rb`

**Step 1: Write the failing test**

Create `spec/jobs/summarize_transcript_job_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe SummarizeTranscriptJob, type: :job do
  let(:user) { create(:user) }
  let(:agent) { create(:agent, user: user) }
  let(:transcript) { create(:transcript, agent: agent, status: :completed) }

  it "calls Summarizer for the transcript" do
    summarizer = instance_double(Summarizer)
    allow(Summarizer).to receive(:new).with(transcript).and_return(summarizer)
    expect(summarizer).to receive(:summarize)

    described_class.perform_now(transcript.id)
  end

  it "skips non-existent transcripts" do
    expect { described_class.perform_now(999999) }.not_to raise_error
  end

  it "skips active transcripts" do
    transcript.update!(status: :active)
    expect(Summarizer).not_to receive(:new)
    described_class.perform_now(transcript.id)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/jobs/summarize_transcript_job_spec.rb`
Expected: FAIL (the placeholder job doesn't do anything).

**Step 3: Implement**

Update `app/jobs/summarize_transcript_job.rb`:
```ruby
class SummarizeTranscriptJob < ApplicationJob
  queue_as :default

  def perform(transcript_id)
    transcript = Transcript.find_by(id: transcript_id)
    return unless transcript&.completed?

    Summarizer.new(transcript).summarize
  end
end
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/jobs/summarize_transcript_job_spec.rb`
Expected: PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: implement SummarizeTranscriptJob"
```

---

### Task 16: Memory Search API

**Files:**
- Create: `app/services/memory_search_service.rb`
- Create: `app/controllers/api/v1/memories_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/services/memory_search_service_spec.rb`
- Create: `spec/requests/api/v1/memories_spec.rb`

**Step 1: Write the failing tests**

Create `spec/services/memory_search_service_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe MemorySearchService do
  let(:user) { create(:user) }
  let(:agent1) { create(:agent, user: user, name: "auth-agent") }
  let(:agent2) { create(:agent, user: user, name: "db-agent") }
  let(:transcript1) { create(:transcript, agent: agent1) }
  let(:transcript2) { create(:transcript, agent: agent2) }

  let(:query_embedding) { Array.new(1536) { 0.0 } }

  before do
    # Auth-related chunk
    create(:memory_chunk, agent: agent1, transcript: transcript1,
      topic: "OAuth implementation",
      summary: "Implemented OAuth2 with PKCE flow",
      skills_demonstrated: ["oauth", "security"],
      embedding: Array.new(1536) { |i| i == 0 ? 1.0 : 0.0 })

    # DB-related chunk
    create(:memory_chunk, agent: agent2, transcript: transcript2,
      topic: "Database optimization",
      summary: "Optimized slow queries",
      skills_demonstrated: ["postgresql", "performance"],
      embedding: Array.new(1536) { |i| i == 1 ? 1.0 : 0.0 })

    allow_any_instance_of(EmbeddingService).to receive(:embed)
      .and_return(Array.new(1536) { |i| i == 0 ? 0.9 : 0.0 })
  end

  it "returns memory chunks ranked by similarity" do
    results = described_class.new(user: user, query: "oauth authentication").search

    expect(results.first.topic).to eq("OAuth implementation")
  end

  it "filters by agent_id" do
    results = described_class.new(user: user, query: "anything", agent_id: agent2.id).search

    expect(results.map(&:topic)).to eq(["Database optimization"])
  end

  it "filters by skills" do
    results = described_class.new(user: user, query: "anything", skills: ["postgresql"]).search

    expect(results.map(&:topic)).to eq(["Database optimization"])
  end

  it "respects limit" do
    results = described_class.new(user: user, query: "anything", limit: 1).search
    expect(results.length).to eq(1)
  end
end
```

Create `spec/requests/api/v1/memories_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Api::V1::Memories", type: :request do
  let(:user) { create(:user) }
  let(:agent) { create(:agent, user: user) }
  let(:transcript) { create(:transcript, agent: agent) }

  before do
    create(:memory_chunk, agent: agent, transcript: transcript,
      topic: "auth work", embedding: Array.new(1536) { 0.1 })

    allow_any_instance_of(EmbeddingService).to receive(:embed)
      .and_return(Array.new(1536) { 0.1 })
  end

  describe "GET /api/v1/memories/search" do
    it "returns search results" do
      get "/api/v1/memories/search", headers: auth_headers(user), params: { query: "authentication" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["topic"]).to eq("auth work")
      expect(body.first["agent_name"]).to be_present
    end

    it "returns 400 without query" do
      get "/api/v1/memories/search", headers: auth_headers(user)
      expect(response).to have_http_status(:bad_request)
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/memory_search_service_spec.rb spec/requests/api/v1/memories_spec.rb`
Expected: FAIL.

**Step 3: Implement**

Create `app/services/memory_search_service.rb`:
```ruby
class MemorySearchService
  def initialize(user:, query:, agent_id: nil, skills: nil, limit: 10)
    @user = user
    @query = query
    @agent_id = agent_id
    @skills = skills
    @limit = limit.to_i.clamp(1, 100)
  end

  def search
    query_embedding = EmbeddingService.new.embed(@query)

    scope = MemoryChunk.joins(:agent).where(agents: { user_id: @user.id })
    scope = scope.where(agent_id: @agent_id) if @agent_id
    scope = scope.where("skills_demonstrated && ARRAY[?]::text[]", @skills) if @skills&.any?

    scope.nearest_neighbors(:embedding, query_embedding, distance: "cosine").first(@limit)
  end
end
```

Create `app/controllers/api/v1/memories_controller.rb`:
```ruby
module Api
  module V1
    class MemoriesController < BaseController
      def search
        unless params[:query].present?
          return render json: { error: "query parameter is required" }, status: :bad_request
        end

        results = MemorySearchService.new(
          user: current_user,
          query: params[:query],
          agent_id: params[:agent_id],
          skills: params[:skills],
          limit: params[:limit] || 10
        ).search

        render json: results.map { |chunk|
          {
            id: chunk.id,
            topic: chunk.topic,
            summary: chunk.summary,
            skills_demonstrated: chunk.skills_demonstrated,
            agent_id: chunk.agent_id,
            agent_name: chunk.agent.name,
            transcript_id: chunk.transcript_id,
            message_range_start: chunk.message_range_start,
            message_range_end: chunk.message_range_end,
            created_at: chunk.created_at
          }
        }
      end
    end
  end
end
```

Add route to `config/routes.rb` (inside `api/v1` namespace):
```ruby
get "memories/search", to: "memories#search"
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/services/memory_search_service_spec.rb spec/requests/api/v1/memories_spec.rb`
Expected: PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add semantic memory search API"
```

---

### Task 17: Sidekiq Configuration

**Files:**
- Create: `config/initializers/sidekiq.rb`
- Create: `config/sidekiq.yml`
- Modify: `config/application.rb`

**Step 1: Create Sidekiq config**

Create `config/sidekiq.yml`:
```yaml
:concurrency: 5
:queues:
  - default
  - summarization
```

Create `config/initializers/sidekiq.rb`:
```ruby
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end
```

In `config/application.rb`, set the queue adapter:
```ruby
config.active_job.queue_adapter = :sidekiq
```

**Step 2: Verify Sidekiq starts**

Run: `bundle exec sidekiq -C config/sidekiq.yml` (briefly, then Ctrl+C)
Expected: Sidekiq starts and connects to Redis.

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: configure Sidekiq for background job processing"
```

---

### Task 18: Final Routes Cleanup and Full Test Suite Run

**Files:**
- Modify: `config/routes.rb` (verify final state)

**Step 1: Verify final routes**

The final `config/routes.rb` should look like:
```ruby
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :agents, only: [:index, :show, :create] do
        member do
          get :memories
          get :transcripts
        end
      end

      resources :transcripts, only: [:show, :create, :update] do
        resources :messages, only: [:index, :create]
      end

      post "transcripts/import", to: "transcripts#import"
      get "memories/search", to: "memories#search"
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
```

**Step 2: Run full test suite**

Run: `bundle exec rspec`
Expected: All tests PASS.

**Step 3: Run routes check**

Run: `rails routes | grep api`
Expected: All defined endpoints are listed.

**Step 4: Commit if any cleanup was needed**

```bash
git add -A
git commit -m "chore: finalize routes and clean up"
```

---

### Summary

| Task | What it builds |
|------|---------------|
| 1 | Rails scaffold + gems + RSpec + pgvector |
| 2 | User model with API key auth |
| 3 | Agent model with lineage |
| 4 | Transcript model |
| 5 | Message model with ordering |
| 6 | MemoryChunk model with pgvector search |
| 7 | API authentication (BaseController) |
| 8 | Agents CRUD API |
| 9 | Transcripts API (create/update/show) |
| 10 | Messages API (streaming ingestion) |
| 11 | JSONL transcript import service |
| 12 | Import API endpoint |
| 13 | Embedding service |
| 14 | Summarizer service (LLM + embeddings) |
| 15 | SummarizeTranscriptJob |
| 16 | Semantic memory search API |
| 17 | Sidekiq configuration |
| 18 | Final cleanup + full test run |
