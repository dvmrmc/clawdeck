class ApiUsageRecord < ApplicationRecord
  belongs_to :user

  def self.track!(user)
    month = Date.current.strftime("%Y%m").to_i
    upsert(
      { user_id: user.id, month: month, call_count: 1 },
      unique_by: %i[user_id month],
      on_duplicate: Arel.sql("call_count = api_usage_records.call_count + 1")
    )
  end
end
