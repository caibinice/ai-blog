<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { MessageCircle, Send } from 'lucide-vue-next'
import { useHead } from '@unhead/vue'
import { useLocale } from '../lib/useLocale'

interface CommentItem {
  id: number
  displayName: string
  content: string
  createdAt: string
}

const { t } = useLocale()
const form = reactive({ displayName: '', email: '', content: '', website: '' })
const comments = ref<CommentItem[]>([])
const nextCursor = ref<number | null>(null)
const submitting = ref(false)
const status = ref('')

async function load(reset = false) {
  const cursor = reset ? '' : nextCursor.value ? `&cursor=${nextCursor.value}` : ''
  const response = await fetch(`/api/blog/comments?limit=20${cursor}`)
  if (!response.ok) return
  const body = await response.json() as { items: CommentItem[]; nextCursor: number | null }
  comments.value = reset ? body.items : [...comments.value, ...body.items]
  nextCursor.value = body.nextCursor
}

async function submit() {
  submitting.value = true
  status.value = ''
  try {
    const response = await fetch('/api/blog/comments', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(form),
    })
    const body = await response.json().catch(() => ({})) as { detail?: string; displayName?: string }
    if (!response.ok) throw new Error(body.detail || 'Unable to publish')
    form.displayName = ''
    form.email = ''
    form.content = ''
    status.value = '✓ Published'
    await load(true)
  } catch (error) {
    status.value = error instanceof Error ? error.message : 'Unable to publish'
  } finally {
    submitting.value = false
  }
}

onMounted(() => load(true))
useHead(computed(() => ({ title: `${t.value.guestbookTitle} · Fish` })))
</script>

<template>
  <section class="page-section section-shell guestbook-layout">
    <div>
      <header class="page-heading">
        <p class="eyebrow">GUESTBOOK</p>
        <h1>{{ t.guestbookTitle }}</h1>
        <p>{{ t.guestbookBody }}</p>
      </header>
      <form class="guestbook-form glass-panel" @submit.prevent="submit">
        <label>
          <span>{{ t.name }}</span>
          <input v-model.trim="form.displayName" maxlength="40" autocomplete="name" />
        </label>
        <label>
          <span>{{ t.email }}</span>
          <input v-model.trim="form.email" required maxlength="254" type="email" autocomplete="email" />
        </label>
        <label>
          <span>{{ t.message }}</span>
          <textarea v-model.trim="form.content" required minlength="2" maxlength="1000" rows="6" />
        </label>
        <label class="honeypot" aria-hidden="true">
          Website
          <input v-model="form.website" tabindex="-1" autocomplete="off" />
        </label>
        <div class="form-footer">
          <span class="form-status" aria-live="polite">{{ status }}</span>
          <button class="primary-button" type="submit" :disabled="submitting">
            <Send :size="17" /> {{ submitting ? t.submitting : t.submit }}
          </button>
        </div>
      </form>
    </div>

    <div class="comments-panel">
      <h2><MessageCircle :size="20" /> {{ t.comments }}</h2>
      <p v-if="!comments.length" class="empty-state glass-panel">{{ t.emptyComments }}</p>
      <div v-else class="comment-list">
        <article v-for="comment in comments" :key="comment.id" class="comment-card glass-panel">
          <div>
            <strong>{{ comment.displayName }}</strong>
            <time :datetime="comment.createdAt">{{ new Date(comment.createdAt).toLocaleDateString() }}</time>
          </div>
          <p>{{ comment.content }}</p>
        </article>
      </div>
      <button v-if="nextCursor" class="secondary-button load-more" type="button" @click="load(false)">{{ t.loadMore }}</button>
    </div>
  </section>
</template>
