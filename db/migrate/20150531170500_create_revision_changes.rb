class CreateRevisionChanges < ActiveRecord::Migration
  def change
    create_table :be_revisable_revision_changes do |t|
      t.integer     :revision_info_id
      t.integer     :user_id
      t.string      :description
      t.datetime    :change_date
    end

    add_index :be_revisable_revision_changes, :revision_info_id
  end
end
