import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { taskId: Number, taskName: String }

  open() {
    // Open Telegram deep link to chat with Vladimir about this task
    const message = `Hablemos sobre la tarea: "${this.taskNameValue}" (task #${this.taskIdValue})`
    const encoded = encodeURIComponent(message)
    
    // Try Telegram bot deep link first (mobile-friendly)
    const botUsername = "dvmrmc_openclawBot"
    const telegramUrl = `https://t.me/${botUsername}?text=${encoded}`
    
    window.open(telegramUrl, "_blank")
  }
}
