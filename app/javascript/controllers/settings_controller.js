import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ['input', 'toggle', 'deleteForm', 'projectName']

  connect() {
    this.deleteFormTarget.addEventListener('submit', this.confirmDelete.bind(this))
  }

  confirmDelete(e) {
    e.preventDefault()
    const name = prompt('Enter project name to delete.')
    if (name === this.projectNameTarget.innerText) {
      this.deleteFormTarget.submit()
    } else {
      alert('Name is invlalid!')
    }
  }

  copy() {
    navigator.clipboard.writeText(this.inputTarget.value)
  }

  toggle() {
    const type = this.inputTarget.type
    let newType, newText
    if (type === 'password') {
      newType = 'text'
      newText = 'Hide'
    } else {
      newType = 'password'
      newText = 'Show'
    }
    this.inputTarget.setAttribute('type', newType)
    this.toggleTarget.textContent = newText
  }
}
