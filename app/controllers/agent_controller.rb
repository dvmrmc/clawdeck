class AgentController < ApplicationController
  def chat
    @context_task = params[:task_id].present? ? tasks.find_by(id: params[:task_id]) : nil

    # If we have a task context and the user is chatting, proxy to OpenClaw agent
    if @context_task && params[:message_type] == "ask_agent" && params[:message].present?
      return proxy_to_openclaw_agent(params[:message].to_s.strip)
    end

    response = case params[:message_type]
    when "focus"
      build_focus_response
    when "weekly_recap"
      build_weekly_recap_response
    when "ask_agent"
      build_ask_response(params[:message].to_s.strip)
    when "task_context"
      build_task_context_response
    else
      render json: { error: "Invalid message_type" }, status: :unprocessable_entity and return
    end

    render json: { response: response, task_context: @context_task&.slice(:id, :name, :status, :priority) }
  end

  private

  def tasks
    @tasks ||= current_user.tasks.unscoped.where(user_id: current_user.id)
  end

  def build_focus_response
    today = Date.current
    lines = []

    # Overdue tasks are top priority
    overdue = tasks.where("due_date < ? AND status != ?", today, Task.statuses[:done])
                   .order(due_date: :asc).limit(5).pluck(:name, :due_date)
    overdue.each do |name, due|
      lines << "#{name} — overdue since #{due.strftime("%b %-d")}"
    end

    # Tasks due today
    due_today = tasks.where(due_date: today).where.not(status: :done)
                     .order(priority: :desc).pluck(:name)
    due_today.each do |name|
      lines << "#{name} — due today"
    end

    # In-progress tasks (already started, keep momentum)
    in_progress = tasks.where(status: :in_progress).order(priority: :desc).limit(5).pluck(:name)
    in_progress.each do |name|
      lines << "#{name} — already in progress" unless lines.length >= 5
    end

    # High priority up_next tasks to fill remaining slots
    if lines.length < 3
      up_next = tasks.where(status: :up_next).order(priority: :desc, position: :asc)
                     .limit(3 - lines.length).pluck(:name, :priority)
      up_next.each do |name, priority|
        label = priority == "high" ? "high priority" : "up next"
        lines << "#{name} — #{label}"
      end
    end

    if lines.empty?
      "You're all clear. No overdue tasks, nothing due today, and nothing in progress. Enjoy the space or pick something from your backlog."
    else
      top = lines.first(3).each_with_index.map { |line, i| "#{i + 1}. #{line}" }
      result = "Here's what needs your attention:\n\n#{top.join("\n")}"
      remaining = tasks.where.not(status: :done).count - top.length
      result += "\n\n#{remaining} other open tasks across your boards." if remaining > 0
      result
    end
  end

  def build_weekly_recap_response
    today = Date.current
    week_start = today.beginning_of_week(:monday)

    completed = tasks.where(status: :done).where("completed_at >= ?", week_start)
    completed_names = completed.limit(5).pluck(:name)
    completed_count = completed.count

    in_flight = tasks.where(status: :in_progress).pluck(:name)
    overdue = tasks.where("due_date < ? AND status != ?", today, Task.statuses[:done]).pluck(:name)
    total_open = tasks.where.not(status: :done).count

    # Agent activity this week
    agent_completions = TaskActivity
      .joins(:task)
      .where(tasks: { user_id: current_user.id })
      .where(actor_type: "agent")
      .where("task_activities.created_at >= ?", week_start)
      .count

    lines = []

    # Completed
    if completed_count > 0
      done_text = completed_names.first(3).join(", ")
      done_text += " and #{completed_count - 3} more" if completed_count > 3
      lines << "Done this week (#{completed_count}): #{done_text}."
    else
      lines << "No tasks completed this week yet."
    end

    # In flight
    if in_flight.any?
      lines << "In progress (#{in_flight.length}): #{in_flight.first(3).join(", ")}#{in_flight.length > 3 ? " and #{in_flight.length - 3} more" : ""}."
    end

    # Needs attention
    if overdue.any?
      lines << "Needs attention: #{overdue.length} overdue — #{overdue.first(3).join(", ")}."
    end

    # Agent contribution
    if agent_completions > 0
      lines << "Your agent handled #{agent_completions} actions this week."
    end

    lines << "#{total_open} tasks still open." if total_open > 0

    lines.join("\n\n")
  end

  def build_task_context_response
    return "No task selected." unless @context_task

    t = @context_task
    lines = []
    lines << "**#{t.name}**"
    lines << "Status: #{t.status.titleize} | Priority: #{(t.priority || 'none').titleize}"
    lines << "Board: #{t.board&.name}"
    lines << ""

    if t.description.present?
      lines << "Notes:"
      lines << t.description
      lines << ""
    end

    # Subtasks
    if t.subtasks.any?
      done = t.subtasks.count(&:done?)
      lines << "Subtasks: #{done}/#{t.subtasks.count} done"
      t.subtasks.each do |s|
        lines << "#{s.done? ? '✅' : '⬜'} #{s.title}"
      end
      lines << ""
    end

    # Recent activity
    activities = t.task_activities.order(created_at: :desc).limit(3)
    if activities.any?
      lines << "Recent activity:"
      activities.each do |a|
        actor = a.actor_type == "agent" ? "🤖 Agent" : "👤 You"
        lines << "#{actor}: #{a.action} #{a.detail}".strip
      end
    end

    lines << ""
    lines << "What would you like to do with this task? You can ask me to break it down, plan next steps, or update it."
    lines.join("\n")
  end

  def build_ask_response(message)
    return "Try asking about your tasks, or use the focus and recap actions." if message.blank?

    # If we have task context, prepend it to make responses task-aware
    if @context_task
      return build_task_aware_response(message)
    end

    q = message.downcase

    if q.match?(/overdue|late|missed|behind/)
      overdue = tasks.where("due_date < ? AND status != ?", Date.current, Task.statuses[:done])
                     .order(due_date: :asc).pluck(:name, :due_date)
      if overdue.any?
        lines = overdue.first(5).map { |name, due| "#{name} — due #{due.strftime("%b %-d")}" }
        "You have #{overdue.length} overdue tasks:\n\n#{lines.join("\n")}"
      else
        "No overdue tasks. You're on track."
      end

    elsif q.match?(/progress|working|doing|current/)
      in_progress = tasks.where(status: :in_progress).pluck(:name)
      if in_progress.any?
        "Currently in progress (#{in_progress.length}):\n\n#{in_progress.first(5).join("\n")}"
      else
        "Nothing in progress right now."
      end

    elsif q.match?(/done|complete|finish/)
      week_start = Date.current.beginning_of_week(:monday)
      done = tasks.where(status: :done).where("completed_at >= ?", week_start).pluck(:name)
      if done.any?
        "Completed this week (#{done.length}):\n\n#{done.first(5).join("\n")}"
      else
        "Nothing completed this week yet."
      end

    elsif q.match?(/board|project/)
      boards = current_user.boards.includes(:tasks)
      lines = boards.map do |b|
        open_count = b.tasks.reject(&:completed).length
        "#{b.icon} #{b.name} — #{open_count} open tasks"
      end
      lines.join("\n")

    elsif q.match?(/blocked|stuck|help/)
      blocked = tasks.where(blocked: true).where.not(status: :done).pluck(:name)
      if blocked.any?
        "Blocked tasks (#{blocked.length}):\n\n#{blocked.first(5).join("\n")}"
      else
        "No blocked tasks right now."
      end

    elsif q.match?(/agent|openclaw/)
      if current_user.agent_last_active_at.present?
        name = current_user.agent_name || "Agent"
        emoji = current_user.agent_emoji || "🦞"
        ago = time_ago_in_words(current_user.agent_last_active_at)
        assigned = tasks.where(assigned_to_agent: true, completed: false).count
        "#{emoji} #{name} was last active #{ago} ago. #{assigned} tasks currently assigned to your agent."
      else
        "No agent connected yet. Go to Settings to set up your OpenClaw integration."
      end

    elsif q.match?(/how many|count|total|stat/)
      total = tasks.where.not(status: :done).count
      by_status = tasks.where.not(status: :done).group(:status).count
      lines = by_status.map { |status, count| "#{status.titleize}: #{count}" }
      "#{total} open tasks:\n\n#{lines.join("\n")}"

    else
      total_open = tasks.where.not(status: :done).count
      in_progress = tasks.where(status: :in_progress).count
      "You have #{total_open} open tasks, #{in_progress} in progress. Try asking about what's overdue, in progress, blocked, or what your boards look like."
    end
  end

  def build_task_aware_response(message)
    t = @context_task
    q = message.downcase

    if q.match?(/break.*down|subtask|split|decompose|steps/)
      "Here's how I'd break down \"#{t.name}\":\n\n1. Research and gather requirements\n2. Draft initial approach\n3. Execute the main work\n4. Review and validate\n5. Mark complete\n\nWant me to create these as subtasks?"

    elsif q.match?(/status|move|progress|update/)
      statuses = %w[inbox up_next in_progress in_review done]
      current_idx = statuses.index(t.status) || 0
      next_status = statuses[[current_idx + 1, statuses.length - 1].min]
      "Task is currently: #{t.status.titleize}.\nNext logical step: #{next_status.titleize}.\n\nShould I move it forward?"

    elsif q.match?(/priority|urgent|important/)
      "Current priority: #{(t.priority || 'none').titleize}.\n\nChange to: none, low, medium, or high?"

    elsif q.match?(/done|complete|finish|close/)
      "I'll mark \"#{t.name}\" as done. ✅"

    elsif q.match?(/block|stuck|help/)
      "I'll mark this as blocked so it gets attention. What's blocking it?"

    elsif q.match?(/note|description|add|detail/)
      "Current notes:\n#{t.description.present? ? t.description : '(empty)'}\n\nWhat would you like to add?"

    else
      "Talking about: **#{t.name}** (#{t.status.titleize})\n\nI can help you:\n• Break it down into subtasks\n• Update its status or priority\n• Add notes or context\n• Mark it done\n\nWhat would you like to do?"
    end
  end

  # Proxy chat to OpenClaw agent with task context
  def proxy_to_openclaw_agent(message)
    t = @context_task
    gateway_token = "7af12a5f57f0fe096689e4a16dcad100eef77e0cc0fd3b14"
    clawdeck_token = current_user.api_tokens.first&.token

    # Build context-rich system prompt
    system_prompt = <<~SYSTEM
      You are helping plan a task in ClawDeck. Be concise and practical.

      Task ##{t.id}: "#{t.name}"
      Status: #{t.status} | Priority: #{t.priority || 'none'} | Board: #{t.board&.name}
      Current notes: #{t.description.present? ? t.description : '(empty)'}
      #{t.subtasks.any? ? "Subtasks: #{t.subtasks.map { |s| "#{s.done? ? '✅' : '⬜'} #{s.title}" }.join(', ')}" : ''}

      Help the user plan this task. When you produce a plan, format it as structured markdown with clear action items.
      Keep responses short and actionable. Speak in the same language as the user.
    SYSTEM

    begin
      require "net/http"
      require "json"

      uri = URI("http://127.0.0.1:18789/v1/chat/completions")
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = 60

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{gateway_token}"
      request.body = {
        model: "openclaw:main",
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: message }
        ]
      }.to_json

      response = http.request(request)

      if response.code.to_i == 200
        data = JSON.parse(response.body)
        agent_response = data.dig("choices", 0, "message", "content") || "No response."

        # Auto-update task description with the plan if it looks substantial
        if agent_response.length > 100 && message.downcase.match?(/plan|break|step|acción|desglos|organiz/)
          new_desc = t.description.present? ? "#{t.description}\n\n---\n\n## Plan de Acción\n\n#{agent_response}" : "## Plan de Acción\n\n#{agent_response}"
          t.update(description: new_desc)

          render json: {
            response: agent_response,
            task_updated: true,
            task_context: { id: t.id, name: t.name, status: t.status }
          }
        else
          render json: {
            response: agent_response,
            task_updated: false,
            task_context: { id: t.id, name: t.name, status: t.status }
          }
        end
      else
        Rails.logger.error("OpenClaw API error: #{response.code} #{response.body}")
        render json: { response: build_task_aware_response(message) }
      end
    rescue => e
      Rails.logger.error("OpenClaw proxy error: #{e.message}")
      render json: { response: build_task_aware_response(message) }
    end
  end
end
