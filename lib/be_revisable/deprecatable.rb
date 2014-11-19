require 'active_support/concern'
module BeRevisable
  module Deprecatable
    extend ActiveSupport::Concern

    # Creates and returns a new deprecating draft out from the invoking revision.
    # A deprecating draft must always have a released-at time as it is expected to be a released revision
    # Once applied, a deprecating draft creates a retroactive change in the deprecated revision (as if the deprecated revision was edited).
    # @return [BeRevisable::Revisable] The created retroactive draft
    def create_deprecating_draft!
      deprecating_draft = nil
      ActiveRecord::Base.transaction do
        deprecating_draft = create_duplicated_revision(:set_as_deprecating_draft)
        deprecating_draft.revision_info.released_at = released_at || DateTime.now # Default now if not creating out of a released revision as
        deprecating_draft.revision_info.expired_at = expired_at
        deprecating_draft.revision_info.save! unless deprecating_draft.new_record?
      end
      deprecating_draft
    end

    def deprecator_of
      deprecation_revisions(:deprecator_of)
    end

    def deprecated_by_revisions
      deprecation_revisions(:deprecated_by_revisions)
    end

    # Return the full list of all revisions this revision is deprecating including recursively all revisions that were deprecated by them as well.
    # Ordered from the direct revision being deprecated to the earliest one that was deprecated by this chain.
    def deprecator_of_chain
      deprecation_revisions(:deprecator_of_chain)
    end

    # Return the full list of all revisions this revision was deprecated by and recursively the revisions that deprecated the rest of those revisions.
    # Ordered from the initial deprecator to the latest deprecator (i.e. the active one)
    def deprecated_by_revisions_chain
      deprecation_revisions(:deprecated_by_revisions_chain)
    end

    # Update the released_at & expired_at times of the deprecating draft.
    # Allow setting a non expired time or a future time.
    # @param [DateTime] released_at - The time to set as released-at time
    # @param [DateTime] expired_at - The time to set as expired-at time (accept nil)
    # @raise RuntimeError if executed for a non-deprecated-draft, a released-at time is not set, expired is before released-at or times are in
    def update_deprecating_draft_datetime_range(released_at, expired_at)
      raise 'Only deprecating draft can be set with datetime range' unless deprecating_draft?
      raise 'Must set a released-at time for a deprecating draft' if released_at.nil?

      revision_info.update_attributes!(:released_at => released_at, :expired_at => expired_at)
    end


    # Return a list of active-revisions that are affected by the retroactive change as it is defined now, including the one that is being directly modified.
    # For example, if there is an expired revision for January and a released revision for February, and the last is being modified to start mid-January, then both those revisions will be affected by this change.
    # @raise [RuntimeError] if not invoked on a "deprecating draft"
    def affected_revisions
      raise 'Affected revisions may apply only to a deprecating draft' unless deprecating_draft?

      # Intersect only on actual affected revision by lowering the range with 1 second of each side
      revision_set.revisions_between(released_at..(expired_at||DateTime.now)-1.second)
    end

    # Applies the deprecating (i.e. retroactive) change.
    # Will deprecate all affected revisions and may create additional new revisions in case there are more affected revisions then the direct one.
    # @param [Integer] user_id - The user applying the deprecation
    # @param [Boolean] avoid_overwriting_primary_draft - Force not overwriting primary-draft even if that is required
    def apply_deprecating_change!(user_id, avoid_overwriting_primary_draft = false)
      affected_revs = []
      ActiveRecord::Base.transaction do
        affected_revs = apply_affected_revisions(user_id)
        apply_as_released(user_id)
        overwrite_primary_draft if !avoid_overwriting_primary_draft && should_overwrite_primary_draft?
      end
      RevisionRetroactiveChangeNotifier.notify(self.class.name, revision_set.id, affected_revs.map(&:id))
      true
    end

    # Return the user deprecated this version, if such exists
    def deprecated_by
      deprecated_by_revisions.first.try(:released_by)
    end


    protected


    private
    # Generic method to get deprecation objects according to the given method
    def deprecation_revisions(method)
      revision_info.send(method).flat_map(&:revision).uniq
    end

    # Check if this revision has been released after (significantly) the given revision
    def released_after?(revision)
      released_at > revision.released_at
    end

    # Check if this revision expired after (significantly) the given revision
    def expires_before?(revision)
      return false if expired_at == revision.expired_at # Handles also the nil case
      return false if expired_at.nil? && revision.expired_at.present? # current yet not expired while revision is
      return true if expired_at.present? && revision.expired_at.nil? # current expired but revision isn't yet

      expired_at < revision.expired_at
    end


    # Create and apply a deprecating revision for the given revision with the given parameters
    # Should be called upon applying a deprecation to create additional deprecations for affected revisions.
    # @param [BeRevisable::Revisable] revision - The revision to create a deprecating revision for
    # @param [DateTime] released_at - The released_at time to set for the deprecating revision
    # @param [DateTime] expired_at - The expired_at time to set for the deprecating revision
    # @param [BeRevisable::RevisionInfo::Status] status - The status to set for the deprecating revision
    # @param [Integer] user_id - The user applying the deprecation
    # @return [BeRevisable::Revisable] The created & applied new revision
    def create_and_apply_deprecating_revision(revision, released_at, expired_at, status, user_id)
      deprecate_revision(revision)

      deprecating_revision = revision.revisable_dup
      deprecating_revision.revision_info.released_at = released_at
      deprecating_revision.revision_info.expired_at = expired_at
      deprecating_revision.revision_info.status = status
      deprecating_revision.revision_info.released_by = user_id
      revision.new_record? ? add_revision_to_revision_set(deprecating_revision) : deprecating_revision.save!

      return deprecating_revision
    end

    # Create and apply a deprecating revision for a revision that comes before this deprecating-draft (which is about to become a released revision)
    # Should be called upon applying a deprecation to create additional deprecations for affected revisions.
    # The new revision should begin at the same time of the deprecated revision, and end when this deprecating draft begins and thus always Expired.
    # @param [BeRevisable::Revisable] revision - The revision to create a deprecating revision for
    # @param [Integer] user_id - The user applying the deprecation
    # @return [BeRevisable::Revisable] The created & applied new revision
    def create_and_apply_before_deprecating_revision(revision, user_id)
      create_and_apply_deprecating_revision(revision, revision.released_at, released_at, RevisionInfo::Status::EXPIRED, user_id)
    end

    # Create and apply a deprecating revision for a revision that comes after this deprecating-draft (which is about to become a released revision)
    # Should be called upon applying a deprecation to create additional deprecations for affected revisions.
    # The new revision should begin at the end time of this deprecating draft and end at the same time of the deprecated revision, while maintaining its status.
    # @param [BeRevisable::Revisable] revision - The revision to create a deprecating revision for
    # @param [Integer] user_id - The user applying the deprecation
    # @param [BeRevisable::RevisionInfo::Status] status - The status to apply to the deprecating revision
    # @return [BeRevisable::Revisable] The created & applied new revision
    def create_and_apply_after_deprecating_revision(revision, user_id, status)
      create_and_apply_deprecating_revision(revision, expired_at, revision.expired_at, status, user_id)
    end

    # Deprecate the given revision by the given list of deprecating revisions
    # @param [BeRevisable::Revisable] revision - The revision to deprecate
    def deprecate_revision(revision)
      revision.revision_info.expired_at ||= DateTime.now
      revision.revision_info.status = RevisionInfo::Status::DEPRECATED
      revision.revision_info.deprecated_at = DateTime.now
      revision.revision_info.save! unless revision.new_record?
    end


    # Apply the deprecation on all affected released revisions
    # @param [Integer] user_id - The user applying the deprecation
    # @param [Array<BeRevisable::Revisable>] The full list of all affected revisions (deprecated & new)
    def apply_affected_revisions(user_id)
      affected_revs = affected_revisions
      all_affected_revisions = affected_revs.clone
      all_affected_revisions << self
      affected_revs.each do |affected_revision|
        # case 1 - This deprecating revision is completely fully included in the handled revision (requires a 'split' of the this deprecated revision)
        if fully_included_in_revision?(affected_revision)
          apply_affected_revision_fully_included_in_revision(affected_revision, user_id, all_affected_revisions)

        # case 2 - This deprecating revision is completely overwriting (full overlap) the handled revision.
        # This case also considers the same exact time frame.
        elsif fully_overwriting_revision?(affected_revision)
          apply_affected_revision_fully_overwriting_revision(affected_revision)

        # case 3 - This deprecating revision overwrites only the end of the handled revision (overwritten revision should be set with shorter expired time and must be set as Expired)
        elsif partially_overwriting_revision_end?(affected_revision)
          apply_affected_revision_partially_overwriting_revision_end(affected_revision, user_id, all_affected_revisions)

        # case 4 - This deprecating revision overwrites only the beginning of the handled revision (overwritten revision should be set with shorter released time and left with the same status)
        elsif partially_overwriting_revision_beginning(affected_revision)
          apply_affected_revision_partially_overwriting_revision_beginning(affected_revision, user_id, all_affected_revisions)

        end
      end
      return all_affected_revisions
    end

    # Check if fully included by the given revision 
    def fully_included_in_revision?(affected_revision)
      released_after?(affected_revision) && expires_before?(affected_revision)
    end

    # Check if fully overwriting the given revision 
    def fully_overwriting_revision?(affected_revision)
      !released_after?(affected_revision) && !expires_before?(affected_revision)
    end

    # Check if this revision partially overwrites the end of the given revision 
    def partially_overwriting_revision_end?(affected_revision)
      released_after?(affected_revision) && !expires_before?(affected_revision)
    end

    # Check if this revision partially overwrites the beginning of the given revision 
    def partially_overwriting_revision_beginning(affected_revision)
      !released_after?(affected_revision) && expires_before?(affected_revision)
    end

    # Apply the deprecation for the case this revision is fully included by the affected revision
    def apply_affected_revision_fully_included_in_revision(affected_revision, user_id, all_affected_revisions)
      # Should create 2 wrapping revisions around this deprecating draft
      original_status = affected_revision.status
      before_revision = create_and_apply_before_deprecating_revision(affected_revision, user_id)
      after_revision = create_and_apply_after_deprecating_revision(affected_revision, user_id, original_status)
      apply_deprecated_by_revisions(affected_revision, [self, before_revision, after_revision])
      all_affected_revisions << before_revision << after_revision
    end

    # Apply the deprecation for the case this revision is fully overwriting the affected revision
    def apply_affected_revision_fully_overwriting_revision(affected_revision)
      deprecate_revision(affected_revision)
      apply_deprecated_by_revisions(affected_revision, [self])
    end

    # Apply the deprecation for the case this revision partially overwrites the end of the affected revision
    def apply_affected_revision_partially_overwriting_revision_end(affected_revision, user_id, all_affected_revisions)
      deprecating_revision = create_and_apply_before_deprecating_revision(affected_revision, user_id)
      apply_deprecated_by_revisions(affected_revision, [self, deprecating_revision])
      all_affected_revisions << deprecating_revision
    end

    # Apply the deprecation for the case this revision partially overwrites the beginning of the affected revision
    def apply_affected_revision_partially_overwriting_revision_beginning(affected_revision, user_id, all_affected_revisions)
      deprecating_revision = create_and_apply_after_deprecating_revision(affected_revision, user_id, affected_revision.status)
      apply_deprecated_by_revisions(affected_revision, [self, deprecating_revision])
      all_affected_revisions << deprecating_revision
    end

    # Apply the deprecated-by-revisions & deprecator of revisions
    # Should be called upon applying a deprecation to create additional deprecations for affected revisions.
    # @param [Array<BeRevisable::Revisable>] deprecating_revisions - The list of deprecating revisions of the deprecated revision
    def apply_deprecated_by_revisions(revision, deprecating_revisions)
      revision.revision_info.deprecated_by_revisions << deprecating_revisions.map{|revision| revision.send(:revision_info)}

    end

    # Apply the deprecation on this (deprecating draft) by setting it as released
    # @param [Integer] user_id - The user applying the deprecation
    def apply_as_released(user_id)
      revision_info.released_by = user_id
      revision_info.status = expired_at ? RevisionInfo::Status::EXPIRED : RevisionInfo::Status::LATEST_RELEASE
      revision_info.save! unless new_record?
    end

    # Overwrite the primary draft with the current revision's data
    def overwrite_primary_draft
      new_primary_draft = create_duplicated_revision(:set_as_temporary_draft)
      new_primary_draft.overwrite_primary_draft!
    end

    # Whether or not primary draft should be overwritten
    # Should overwrite primary-draft when deprecating change is 'active' / 'ongoing', i.e. not expired
    def should_overwrite_primary_draft?
      ongoing?
    end

  end
end