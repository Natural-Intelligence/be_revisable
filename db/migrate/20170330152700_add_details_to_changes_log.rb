class AddDetailsToChangesLog < ActiveRecord::Migration
  def change
    add_column :be_revisable_revision_changes, :details, :string
  end
end