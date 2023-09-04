# frozen_string_literal: true

class Event < ApplicationRecord
  MESSAGE_MAX_LENGTH = 3000
  BROWSER_JS = 'browser-js'

  belongs_to :project
  belongs_to :user, optional: true
  belongs_to :parent, class_name: 'Event', optional: true, counter_cache: :occurrence_count
  has_many :occurrences, class_name: 'Event', foreign_key: 'parent_id', dependent: :delete_all
  has_one :last_occurrence, -> { order(created_at: :desc) }, class_name: 'Event', foreign_key: 'parent_id'

  attribute :framework, :string, default: :plain

  enum status: %i[active resolved muted]

  validates :title, :status, :framework, presence: true

  scope :by_status, ->(status) { where(status: status) if status.present? }
  scope :by_parent, ->(parent_id) { where(parent_id: parent_id) if parent_id.present? }
  scope :since, ->(time_ago) { where('created_at > :time_ago', time_ago: time_ago) }

  after_create :broadcast_new_event_to_board, if: :parent?
  after_update_commit :broadcast_assignee_to_board, :broadcast_assignee_to_details, if: :user_id_previously_changed?
  after_update_commit :broadcast_status_to_board, :broadcast_status_to_details, if: :status_previously_changed?
  after_destroy_commit -> { broadcast_remove_to project }

  def message=(value)
    message = value.is_a?(String) && value.length > MESSAGE_MAX_LENGTH ? value.truncate(MESSAGE_MAX_LENGTH) : value
    super(message)
  end

  def created_at=(value)
    timestamp = value.is_a?(Integer) ? Time.at(value) : value
    super(timestamp)
  end

  def parent?
    parent_id.nil?
  end

  def occurrence?
    parent_id.present?
  end

  def user_agent?
    (headers && headers['User-Agent']).present?
  end

  def device_detector
    @device_detector ||= DeviceDetector.new(headers['User-Agent']) if user_agent?
  end

  def traces
    @traces ||= backtrace.map { |trace| Chunk.new(trace) }
  end

  def project_trace?
    traces.any?(&:project?)
  end

  def user_browser
    "#{device_detector.name} #{device_detector.full_version}" if device_detector
  end

  def user_os
    "#{device_detector.os_name} #{device_detector.os_full_version}" if device_detector
  end

  def user_device
    "#{device_detector.device_name} #{device_detector.device_type}" if device_detector
  end

  def user_email
    person_data&.dig('email')
  end

  def refer_url
    headers&.dig('Referer')
  end

  private

  def broadcast_new_event_to_board
    broadcast_prepend_to project, target: "#{status}_events_page_1"
  end

  def broadcast_assignee_to_board
    broadcast_replace_later_to project
  end

  def broadcast_assignee_to_details
    broadcast_replace_later target: 'assignee', partial: 'events/assignee'
  end

  def broadcast_status_to_details
    broadcast_replace_later target: 'status', partial: 'events/status'
  end

  def broadcast_status_to_board
    broadcast_remove_to project
    if prior_event_id
      broadcast_after_to project, target: "event_#{prior_event_id}"
    else
      broadcast_prepend_to project, target: "#{status}_events_page_1"
    end
  end

  def prior_event_id
    prior_order = 'COALESCE(last_occurrence_at, created_at) ASC'
    @prior_event_id ||= Event
                        .order(Arel.sql(prior_order))
                        .where('COALESCE(last_occurrence_at, created_at) >= ?', last_occurrence_at || created_at)
                        .where(parent_id: nil, status: status, project_id: project_id)
                        .limit(1)
                        .pluck(Arel.sql("LEAD(id) OVER ( ORDER BY #{prior_order} )"))
                        .first
  end

  def update_occurrences_status
    occurrences.update_all(status: status)
  end

  def update_active_count
    project.update!(active_event_count: project.active_events.size)
  end
end
