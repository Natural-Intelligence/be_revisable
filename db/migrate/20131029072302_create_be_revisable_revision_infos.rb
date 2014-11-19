class CreateBeRevisableRevisionInfos < ActiveRecord::Migration
  def change
    create_table :be_revisable_revision_infos do |t|
      t.string :status
      t.datetime :released_at
      t.integer :released_by
      t.datetime :expired_at
      t.datetime :deprecated_at
      t.references :revision_set
      t.references :revision, polymorphic: true
      t.timestamps
    end
    add_index :be_revisable_revision_infos, :revision_set_id
    add_index :be_revisable_revision_infos, :revision_id
  end
end
