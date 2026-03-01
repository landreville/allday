class AddFieldsToAgents < ActiveRecord::Migration[8.0]
  def change
    add_column :agents, :name, :string, null: false, default: ""
    add_column :agents, :llm_model, :string
    add_column :agents, :model_config, :jsonb, default: {}
    add_column :agents, :parent_id, :bigint
    add_column :agents, :origin, :integer, default: 0, null: false
    add_column :agents, :metadata, :jsonb, default: {}

    add_foreign_key :agents, :agents, column: :parent_id
    add_index :agents, :parent_id
  end
end
