require 'active_support/concern'
module BeRevisable
  module Revisable

    extend ActiveSupport::Concern

    included(nil) do

      def self.revision_set_name
       @revision_set_name ||=  "#{self.name.to_s.underscore.gsub('/', '__')}_revision_set"
      end

      has_one :revision_info, :class_name => ::BeRevisable::RevisionInfo.name.to_s, :as => :revision, :dependent => :destroy, :autosave => false
      has_one revision_set_name.to_sym, :class_name => "::BeRevisable::#{self.name.to_s}RevisionSet", source: :revision_set, :through => :revision_info, :autosave => false


      delegate :primary_draft?, :temporary_draft?, :released?, :latest_release?, :expired?, :deprecated?, :deprecating_draft?, :ongoing?,
               :expired_at, :released_at, :released_by, :status, :deprecated_at, :earliest_release_date,
               :to => :revision_info
      delegate :temporary_drafts, :primary_draft, :latest_release, :expired_releases, :revisions, :to => :revision_set

      amoeba do
        enable
      end

      after_save do
        self.revision_info.revision = self if self.revision_info.revision_id != id
        self.revision_info.save! if self.revision_info.changed? || self.revision_info.new_record?
      end

      scope :revisable, lambda {includes(:revision_info)}

      scope :by_status, lambda { |versions| joins(:revision_info).where("be_revisable_revision_infos.status" => versions) }

      scope :releases, lambda { by_status([::BeRevisable::RevisionInfo::Status::LATEST_RELEASE, ::BeRevisable::RevisionInfo::Status::EXPIRED]) }

      scope :drafts, lambda { by_status(::BeRevisable::RevisionInfo::Status::PRIMARY_DRAFT) }

      scope :revisions_between, lambda { |datetime_range| releases.
          where('be_revisable_revision_infos.released_at <= ?', datetime_range.end).
          where('(be_revisable_revision_infos.expired_at > ? or be_revisable_revision_infos.expired_at is null) ', datetime_range.begin) }

      scope :revisions_of_revision_sets, lambda { |revision_set_ids|
        joins(revision_set_name.to_sym).
            where('be_revisable_revision_sets.id' => revision_set_ids)
      }

      scope :include_revision_set, lambda { includes(revision_set_name) }


      # Deletes the primary draft and change the temporary draft to be a primary draft
      # Raise if not temporary draft
      # Returns true on success, raise on error
      def overwrite_primary_draft!
        raise "Only temporary draft can overwrite primary draft. #{revisable_info}" unless temporary_draft?
        ActiveRecord::Base.transaction do
          primary_draft.destroy
          revision_info.set_as_primary_draft
          revision_info.save! unless new_record?
        end
      end


      # Returns RevisionableObject - creates and returns a new temporary draft
      def create_temporary_draft!
        create_duplicated_revision(:set_as_temporary_draft)
      end

      # Allowed only for primary draft - Raise if not a primary_draft
      # Clones the revision (create primary draft),
      # Change the revision status to LATESt_RELEASE
      # Change the LATEST_RELEASE revision to EXPIRED (if exist)
      # Returns Boolean - true on success, raise on error
      def release!(user_id = nil)
        raise "Only primary draft can be released. #{revisable_info}" unless primary_draft?
        ActiveRecord::Base.transaction do
          replace_time = DateTime.now

          revision_to_expire = latest_release
          unless revision_to_expire.nil?
            revision_to_expire.revision_info.set_as_expired(replace_time)
            revision_to_expire.save! unless new_record?
          end

          revision_info.set_as_latest_release(user_id, replace_time)
          revision_info.save! unless new_record?

          new_draft = revisable_dup
          new_draft.revision_info.set_as_primary_draft

          new_record? ? add_revision_to_revision_set(new_draft) : new_draft.save!
        end
        true
      end

      def revision_set
        return true_revision_set if association(self.class.revision_set_name.to_sym).loaded? && true_revision_set
        revision_info.revision_set
      end

      alias_method :true_revision_set, revision_set_name
      alias_method revision_set_name, :revision_set

      def revision_set=(revision_set)
        association(self.class.revision_set_name.to_sym).reset
        self.revision_info.revision_set= revision_set
      end

      alias_method revision_set_name + '=', :revision_set=

      def revision_info=(revision_info)
        association(self.class.revision_set_name.to_sym).reset
        super
      end

      def release_time_range
        return nil unless released?
        released_at..(expired_at || Time.now)
      end

      # Rollback latest release to it's previous state
      # Primary draft will be Destroyed!
      # Latest release will become primary draft
      # The latest expired release will overwrite the primary draft
      def rollback!
        raise 'Only latest release can be rolled back' unless latest_release?
        ActiveRecord::Base.transaction do
          primary_draft.destroy
          revision_info.set_as_primary_draft
          revision_info.released_at = nil
          revision_info.released_by = nil
          revision_info.save!
          expired_releases.revisable.order('be_revisable_revision_infos.expired_at').last.revision_info.set_as_latest_release(nil, nil, false).save! if expired_releases.size > 0
        end
        true
      end

      protected

      def revision_info
        revision_info_obj = super
        return revision_info_obj unless revision_info_obj.nil?
        revision_info_obj = build_revision_info
        revision_info_obj.revision = self
        self.revision_info = revision_info_obj
      end

      def revisable_dup
        amoeba_dup
      end

      # Adds the new revision to the currency revision set and sets the revision_set of the new revision to point to
      # the currency revision_Set
      #
      # @param [Revisable] revision - the new revision
      def add_revision_to_revision_set(revision)
        revision.revision_set = revision_set
        revision_set.revisions << revision
      end


      # Generic method for creating a new duplicated revision out of this revision
      # @param [Symbol] revision_info_method - An optional method of the revision-info to be called once the new revision was created (e.g. set_as_temporary_draft)
      # @return [BeRevisable::Revisable] The created revision object
      def create_duplicated_revision(revision_info_method = nil)
        new_rev = nil
        ActiveRecord::Base.transaction do
          new_rev = revisable_dup
          new_rev.revision_info.send(revision_info_method) if revision_info_method
          new_record? ? add_revision_to_revision_set(new_rev) : new_rev.save!
        end
        new_rev
      end

      private

      def revisable_info
        revisable_id = self.respond_to?(:id) ? self.id : "not have"
        "Revisable class: #{self.class.name}, id: #{revisable_id}"
      end

    end
  end
end
