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
