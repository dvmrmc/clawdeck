import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["editor", "preview", "textarea", "toggleBtn"]

  toggle() {
    const showing = this.previewTarget.classList.contains("hidden")
    if (showing) {
      // Show preview with rendered markdown (simple client-side)
      const text = this.textareaTarget.value || ""
      this.previewTarget.querySelector(".markdown-body").innerHTML = this.renderMarkdown(text)
      this.editorTarget.classList.add("hidden")
      this.previewTarget.classList.remove("hidden")
      this.toggleBtnTarget.textContent = "Edit"
    } else {
      this.editorTarget.classList.remove("hidden")
      this.previewTarget.classList.add("hidden")
      this.toggleBtnTarget.textContent = "Preview"
    }
  }

  renderMarkdown(text) {
    // Simple markdown rendering for preview
    let html = text
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      // Headers
      .replace(/^### (.+)$/gm, '<h3 style="font-size:14px;font-weight:700;color:#e0e0e0;margin:12px 0 6px">$1</h3>')
      .replace(/^## (.+)$/gm, '<h2 style="font-size:15px;font-weight:700;color:#e0e0e0;margin:14px 0 6px">$1</h2>')
      .replace(/^# (.+)$/gm, '<h1 style="font-size:16px;font-weight:700;color:#e0e0e0;margin:16px 0 8px">$1</h1>')
      // Bold & italic
      .replace(/\*\*(.+?)\*\*/g, '<strong style="color:#e0e0e0">$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      // Code
      .replace(/`(.+?)`/g, '<code style="background:rgba(255,255,255,0.08);padding:2px 5px;border-radius:3px;font-size:11px">$1</code>')
      // Lists
      .replace(/^- (.+)$/gm, '<div style="padding-left:12px;margin:2px 0">• $1</div>')
      // Links
      .replace(/\[(.+?)\]\((.+?)\)/g, '<a href="$2" target="_blank" style="color:#60a5fa">$1</a>')
      // Line breaks
      .replace(/\n\n/g, '<br><br>')
      .replace(/\n/g, '<br>')
    return html
  }
}
