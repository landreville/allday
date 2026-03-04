class AddClientToAgents < ActiveRecord::Migration[8.0]
  def change
    add_column :agents, :client, :string
    add_index :agents, :client
  end
end
