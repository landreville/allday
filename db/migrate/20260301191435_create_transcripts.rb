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
