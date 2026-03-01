# frozen_string_literal: true

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

    add_index :messages, %i[transcript_id sequence], unique: true
  end
end
