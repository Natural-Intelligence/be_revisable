class UpdateRevisionChangesDescription < ActiveRecord::Migration
  def change
    change_column(:be_revisable_revision_changes, :description, :text, limit: 1000)
  end
end
