class UpdatePayloadType < ActiveRecord::Migration
  def change
    change_column(:be_revisable_revision_changes, :payload, :text)
  end
end
