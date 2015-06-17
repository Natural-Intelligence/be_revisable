module BeRevisable
  class RevisionChange < ActiveRecord::Base
    belongs_to :revision_info, inverse_of: :revision_changes
  end
end