// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/pool_lite"
import topbar from "../vendor/topbar"
import "../vendor/qrcode.min.js"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// Custom hooks for poll animations
const Hooks = {
  VoteAnimation: {
    mounted() {
      this.handleEvent("vote-animation", ({option_id, new_percentage, timestamp}) => {
        const progressBar = document.getElementById(`progress-bar-${option_id}`)
        const container = progressBar?.closest('.relative.border.rounded-lg.p-4')
        
        if (progressBar && container) {
          // Add custom CSS property for animation
          progressBar.style.setProperty('--progress-width', `${new_percentage}%`)
          
          // Remove existing animation classes
          progressBar.classList.remove('progress-animate', 'progress-glow', 'vote-success')
          
          // Force reflow
          progressBar.offsetHeight
          
          // Add new animation classes
          progressBar.classList.add('progress-animate', 'progress-shimmer', 'vote-success')
          
          // Add container hover effect
          container.classList.add('vote-success', 'poll-option-hover')
          
          // Create floating vote indicator
          this.createFloatingVote(container, '+1 vote')
          
          // Remove effects after animation
          setTimeout(() => {
            progressBar.classList.remove('progress-animate', 'progress-shimmer', 'vote-success')
            container.classList.remove('vote-success')
          }, 2000)
        }
      })
    },
    
    createFloatingVote(container, text) {
      const floatingEl = document.createElement('div')
      floatingEl.textContent = text
      floatingEl.className = 'absolute top-2 right-2 text-xs font-bold text-green-600 pointer-events-none bounce-in'
      floatingEl.style.zIndex = '50'
      
      container.style.position = 'relative'
      container.appendChild(floatingEl)
      
      // Remove after animation
      setTimeout(() => {
        if (floatingEl.parentNode) {
          floatingEl.remove()
        }
      }, 1500)
    }
  },
  
  ProgressBarAnimator: {
    mounted() {
      // Animate progress bars on mount
      this.animateProgressBars()
    },
    
    updated() {
      // Re-animate when data updates
      this.animateProgressBars()
    },
    
    animateProgressBars() {
      const progressBars = this.el.querySelectorAll('[id*="progress-bar-"]')
      
      progressBars.forEach((bar, index) => {
        // Stagger the animations
        setTimeout(() => {
          const currentWidth = bar.style.width
          bar.style.setProperty('--progress-width', currentWidth)
          
          // Reset and animate
          bar.style.width = '0%'
          bar.offsetHeight // Force reflow
          
          bar.classList.add('progress-animate')
          bar.style.width = currentWidth
          
          // Add shimmer effect for non-zero bars
          if (parseFloat(currentWidth) > 0) {
            bar.classList.add('progress-shimmer')
          }
        }, index * 150) // Stagger by 150ms
      })
    }
  },
  
  // QR Code generation hook
  QRCodeGenerator: {
    mounted() {
      this.generateQRCode()
    },
    
    updated() {
      this.generateQRCode()
    },
    
    generateQRCode() {
      const url = this.el.dataset.url
      if (url && typeof QRCode !== 'undefined') {
        // Clear existing QR code
        this.el.innerHTML = ''
        
        // Generate QR code using QRCode.js library
        new QRCode(this.el, {
          text: url,
          width: 128,
          height: 128,
          colorDark: "#000000",
          colorLight: "#ffffff",
          correctLevel: QRCode.CorrectLevel.M
        })
      } else {
        // Fallback if QRCode library not available
        this.el.innerHTML = `
          <div class="text-gray-400 text-xs text-center">
            <svg class="w-8 h-8 mx-auto mb-1" fill="currentColor" viewBox="0 0 24 24">
              <path d="M3 11h8V3H3v8zm2-6h4v4H5V5zM3 21h8v-8H3v8zm2-6h4v4H5v-4zM21 3h-8v8h8V3zm-2 6h-4V5h4v4zM19 19h2v2h-2zM13 13h2v2h-2zM15 15h2v2h-2zM13 17h2v2h-2zM15 19h2v2h-2zM17 17h2v2h-2zM17 13h2v2h-2zM19 15h2v2h-2z"/>
            </svg>
            QR Code
          </div>
        `
      }
    }
  },
  
  // Copy to clipboard functionality
  CopyToClipboard: {
    mounted() {
      this.el.addEventListener('click', (e) => {
        e.preventDefault()
        const url = this.el.dataset.url
        
        if (navigator.clipboard && window.isSecureContext) {
          // Modern clipboard API
          navigator.clipboard.writeText(url).then(() => {
            this.showCopySuccess()
          }).catch(() => {
            this.fallbackCopy(url)
          })
        } else {
          // Fallback for older browsers
          this.fallbackCopy(url)
        }
      })
    },
    
    fallbackCopy(text) {
      const textArea = document.createElement('textarea')
      textArea.value = text
      textArea.style.position = 'fixed'
      textArea.style.left = '-9999px'
      document.body.appendChild(textArea)
      textArea.select()
      
      try {
        document.execCommand('copy')
        this.showCopySuccess()
      } catch (err) {
        console.error('Copy failed:', err)
      }
      
      document.body.removeChild(textArea)
    },
    
    showCopySuccess() {
      // Show success feedback
      const originalText = this.el.innerHTML
      this.el.innerHTML = `
        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
          <path d="M9 16.2L4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4L9 16.2z"/>
        </svg>
        <span>Copied!</span>
      `
      
      // Add success styling
      this.el.classList.add('bg-green-600', 'text-white')
      this.el.classList.remove('bg-blue-600', 'hover:bg-blue-700')
      
      // Reset after 2 seconds
      setTimeout(() => {
        this.el.innerHTML = originalText
        this.el.classList.remove('bg-green-600', 'text-white')
        this.el.classList.add('bg-blue-600', 'hover:bg-blue-700')
      }, 2000)
    }
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Handle opening URLs (for email sharing)
window.addEventListener("phx:open-url", (e) => {
  window.open(e.detail.url, '_blank')
})

// Handle LiveView push_event for sharing
window.addEventListener("phx:share-content", async (e) => {
  console.log('Received share-content event:', e.detail);
  const { title, description, url } = e.detail
  try {
    await handleSharing(title, description, url)
  } catch (error) {
    console.error('Error in sharing handler:', error);
    // Fallback to simple clipboard copy
    if (navigator.clipboard) {
      await navigator.clipboard.writeText(url);
      showShareMessage('Poll link copied to clipboard!');
    }
  }
})

// Unified sharing handler
async function handleSharing(title, description, url) {
  console.log('Attempting to share:', { title, description, url })
  
  // Try native Web Share API first
  if (navigator.share) {
    try {
      await navigator.share({
        title: title,
        text: `${description}\n\nVote here:`,
        url: url
      })
      console.log('Content shared successfully')
      showShareMessage('Poll shared successfully!')
    } catch (err) {
      console.log('Error sharing content:', err)
      // Fallback to copying URL
      fallbackCopyUrl(url)
    }
  } else {
    // Fallback to copying URL
    fallbackCopyUrl(url)
  }
}

// Fallback function to copy URL to clipboard
function fallbackCopyUrl(url) {
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(url).then(() => {
      showShareMessage('Poll link copied to clipboard!')
    }).catch(() => {
      legacyCopyUrl(url)
    })
  } else {
    legacyCopyUrl(url)
  }
}

// Legacy copy method
function legacyCopyUrl(url) {
  const textArea = document.createElement('textarea')
  textArea.value = url
  textArea.style.position = 'fixed'
  textArea.style.left = '-9999px'
  document.body.appendChild(textArea)
  textArea.select()
  
  try {
    document.execCommand('copy')
    showShareMessage('Poll link copied to clipboard!')
  } catch (err) {
    console.error('Copy failed:', err)
    showShareMessage('Unable to copy link. Please copy manually: ' + url)
  }
  
  document.body.removeChild(textArea)
}

// Show sharing feedback message
function showShareMessage(message) {
  // Create a temporary notification
  const notification = document.createElement('div')
  notification.textContent = message
  notification.className = 'fixed top-4 right-4 bg-green-600 text-white px-4 py-2 rounded-lg shadow-lg z-50 animate-pulse'
  document.body.appendChild(notification)
  
  // Remove after 3 seconds
  setTimeout(() => {
    if (notification.parentNode) {
      notification.remove()
    }
  }, 3000)
}

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

