class AddPayloadToChangesLog < ActiveRecord::Migration
  def change
    add_column :be_revisable_revision_changes, :payload, :string
  end
end