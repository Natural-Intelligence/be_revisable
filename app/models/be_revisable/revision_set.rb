module BeRevisable
  class RevisionSet < ActiveRecord::Base

    has_many :revision_infos, autosave: false, dependent: :destroy, inverse_of: :revision_set

    validates_associated :revision_infos

    after_save do
      if association(:revisions).loaded?
        revisions.each do |revision|
          revision.save! if revision.new_record?
        end
      end
    end

    amoeba do
      enable
    end

    def primary_draft
      draft = revisions_by_status(RevisionInfo::Status::PRIMARY_DRAFT).first

      draft = create_primary_draft_from_latest_release if draft.nil?

      return draft
    end

    # Returns Array<RevisionableObject> - the current temporary drafts of the revision tree
    def temporary_drafts
      revisions_by_status(RevisionInfo::Status::TEMPORARY_DRAFT)
    end

    # Returns a RevisionableObject - the revision that was released the last
    def latest_release
      revisions_by_status(RevisionInfo::Status::LATEST_RELEASE).first
    end

    # Returns an ActiveRelation - all the revisions that where released (active)
    def releases
      revisions_by_status([RevisionInfo::Status::LATEST_RELEASE, RevisionInfo::Status::EXPIRED])
    end


    # @return [ActiveRelation] - all expired releases for the revision set
    def expired_releases
      revisions_by_status(RevisionInfo::Status::EXPIRED)
    end

    # Returns a RevisionableObject - the revision that was LATEST_RELEASED in the given datetime
    def revision_at(datetime)
      revisions_between(datetime..datetime).first
    end

    def revisions_between(datetime_range)
      releases.
          where('be_revisable_revision_infos.released_at <= ?', datetime_range.end).
          where('(be_revisable_revision_infos.expired_at > ? or be_revisable_revision_infos.expired_at is null) ', datetime_range.begin).
          order('be_revisable_revision_infos.released_at')
    end

    protected

    def revisions_by_status(status)
      if new_record?
        status_array = Array(status)
        return revisions.select{|rev| status_array.include?(rev.status)}
      else
        return revisions.where('be_revisable_revision_infos.status' => status)
      end

    end


    def create_primary_draft_from_latest_release
      release_to_clone = latest_release
      raise 'No primary draft or latest release in the revision set' if release_to_clone.nil?
      new_primary_draft = release_to_clone.clone
      new_primary_draft.save!
      return new_primary_draft
    end
  end
end