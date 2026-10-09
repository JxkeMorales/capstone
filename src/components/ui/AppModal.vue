<script setup>
import { ref, watch, onBeforeUnmount, nextTick } from 'vue'
import { X } from 'lucide-vue-next'

const props = defineProps({
  modelValue: {
    type: Boolean,
    default: false
  },
  title: {
    type: String,
    default: ''
  },
  maxWidth: {
    type: String,
    default: 'max-w-lg'
  },
  showClose: {
    type: Boolean,
    default: true
  },
  closeOnBackdrop: {
    type: Boolean,
    default: true
  }
})

const emit = defineEmits(['update:modelValue', 'close'])

const modalRef = ref(null)
const previousActiveElement = ref(null)
const titleId = `app-modal-title-${Math.random().toString(36).slice(2, 9)}`

const getFocusableElements = () => {
  if (!modalRef.value) return []
  return Array.from(
    modalRef.value.querySelectorAll(
      'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
    )
  )
}

const handleKeyDown = (e) => {
  if (!props.modelValue) return

  if (e.key === 'Escape') {
    e.preventDefault()
    close()
    return
  }

  if (e.key === 'Tab') {
    const focusable = getFocusableElements()
    if (focusable.length === 0) {
      e.preventDefault()
      return
    }

    const firstElement = focusable[0]
    const lastElement = focusable[focusable.length - 1]

    if (e.shiftKey) {
      if (document.activeElement === firstElement || !modalRef.value.contains(document.activeElement)) {
        e.preventDefault()
        lastElement.focus()
      }
    } else {
      if (document.activeElement === lastElement || !modalRef.value.contains(document.activeElement)) {
        e.preventDefault()
        firstElement.focus()
      }
    }
  }
}

const open = () => {
  previousActiveElement.value = document.activeElement
  document.body.style.overflow = 'hidden'
  const appRoot = document.getElementById('app')
  if (appRoot) {
    appRoot.setAttribute('aria-hidden', 'true')
  }

  nextTick(() => {
    window.addEventListener('keydown', handleKeyDown)
    const focusable = getFocusableElements()
    if (focusable.length > 0) {
      focusable[0].focus()
    } else if (modalRef.value) {
      modalRef.value.focus()
    }
  })
}

const close = () => {
  window.removeEventListener('keydown', handleKeyDown)
  document.body.style.overflow = ''
  const appRoot = document.getElementById('app')
  if (appRoot) {
    appRoot.removeAttribute('aria-hidden')
  }

  emit('update:modelValue', false)
  emit('close')

  nextTick(() => {
    if (previousActiveElement.value && typeof previousActiveElement.value.focus === 'function') {
      previousActiveElement.value.focus()
    }
  })
}

const onBackdropClick = (e) => {
  if (props.closeOnBackdrop && e.target === e.currentTarget) {
    close()
  }
}

watch(() => props.modelValue, (isOpen) => {
  if (isOpen) {
    open()
  } else {
    close()
  }
})

onBeforeUnmount(() => {
  window.removeEventListener('keydown', handleKeyDown)
  document.body.style.overflow = ''
  const appRoot = document.getElementById('app')
  if (appRoot) {
    appRoot.removeAttribute('aria-hidden')
  }
})
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div 
        v-if="modelValue" 
        class="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6 overflow-y-auto m3-scrim-overlay"
        @click="onBackdropClick"
      >
        <div 
          ref="modalRef"
          tabindex="-1"
          role="dialog"
          aria-modal="true"
          :aria-labelledby="title ? titleId : undefined"
          class="relative w-full m3-surface-modal rounded-[28px] border border-[var(--md-outline-variant)] shadow-xl overflow-hidden focus:outline-none"
          :class="maxWidth"
          @click.stop
        >
          <!-- Header -->
          <div v-if="title || $slots.header" class="px-6 pt-6 pb-4 flex items-center justify-between border-b border-[var(--md-outline-variant)]/40">
            <slot name="header">
              <h2 :id="titleId" class="text-lg font-semibold tracking-tight text-[var(--md-on-surface)]">
                {{ title }}
              </h2>
            </slot>
            <button 
              v-if="showClose"
              type="button"
              @click="close"
              class="min-w-[44px] min-h-[44px] rounded-full flex items-center justify-center text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container-high)] transition-colors cursor-pointer"
              aria-label="Close dialog"
            >
              <X class="w-5 h-5" />
            </button>
          </div>

          <!-- Body -->
          <div class="px-6 py-5 max-h-[calc(85vh-120px)] overflow-y-auto">
            <slot />
          </div>

          <!-- Footer -->
          <div v-if="$slots.footer" class="px-6 py-4 border-t border-[var(--md-outline-variant)]/40 flex items-center justify-end gap-3 bg-[var(--md-surface-container)]">
            <slot name="footer" />
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
