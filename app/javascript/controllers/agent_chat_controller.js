import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { taskId: Number, taskName: String }

  open() {
    // Dispatch a custom event that command_bar_controller listens for
    // Opens command bar in agent mode with task context
    const event = new CustomEvent("command-bar:open-task-chat", {
      detail: {
        taskId: this.taskIdValue,
        taskName: this.taskNameValue
      },
      bubbles: true
    })
    document.dispatchEvent(event)
  }
}
