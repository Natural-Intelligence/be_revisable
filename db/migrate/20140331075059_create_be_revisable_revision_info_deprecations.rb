class CreateBeRevisableRevisionInfoDeprecations < ActiveRecord::Migration
  def change
    create_table :be_revisable_info_deprecations do |t|
      t.integer :deprecator_of_revision_info_id
      t.integer :deprecated_by_revision_info_id
    end

    add_index :be_revisable_info_deprecations, :deprecator_of_revision_info_id, :name => 'index_be_revisable_info_deprecations_on_deprecator_of'
    add_index :be_revisable_info_deprecations, :deprecated_by_revision_info_id, :name => 'index_be_revisable_info_deprecations_on_deprecated_by_revision'
  end
end
