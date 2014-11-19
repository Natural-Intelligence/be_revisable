class CreateBeRevisableRevisionSets < ActiveRecord::Migration
  def change
    create_table :be_revisable_revision_sets do |t|
      t.string :type

      t.timestamps
    end
  end
end
