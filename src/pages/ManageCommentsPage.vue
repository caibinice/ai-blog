<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { KeyRound, LogOut, Trash2 } from 'lucide-vue-next'

interface AdminComment {
  id: number
  displayName: string
  email: string
  content: string
  createdAt: string
}

const token = ref('')
const comments = ref<AdminComment[]>([])
const error = ref('')
const authenticated = ref(false)

async function load() {
  error.value = ''
  try {
    const response = await fetch('/api/blog/admin/comments?limit=100', {
      headers: { Authorization: `Bearer ${token.value}` },
    })
    if (!response.ok) throw new Error('管理令牌无效')
    const body = await response.json() as { items: AdminComment[] }
    comments.value = body.items
    authenticated.value = true
    sessionStorage.setItem('fish-blog-admin-token', token.value)
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : '加载失败'
  }
}

async function remove(id: number) {
  if (!window.confirm('确定删除这条留言？')) return
  const response = await fetch(`/api/blog/admin/comments/${id}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token.value}` },
  })
  if (response.ok) comments.value = comments.value.filter((item) => item.id !== id)
}

function logout() {
  sessionStorage.removeItem('fish-blog-admin-token')
  token.value = ''
  comments.value = []
  authenticated.value = false
}

onMounted(() => {
  token.value = sessionStorage.getItem('fish-blog-admin-token') || ''
  if (token.value) void load()
})
</script>

<template>
  <section class="page-section section-shell admin-page">
    <header class="page-heading page-heading-row">
      <div>
        <p class="eyebrow">PRIVATE</p>
        <h1>留言管理</h1>
        <p>邮箱只在此管理界面显示。</p>
      </div>
      <button v-if="authenticated" type="button" class="secondary-button compact-button" @click="logout">
        <LogOut :size="16" /> 退出
      </button>
    </header>

    <form v-if="!authenticated" class="admin-login glass-panel" @submit.prevent="load">
      <KeyRound :size="24" />
      <label>
        <span>管理令牌</span>
        <input v-model="token" type="password" required autocomplete="current-password" />
      </label>
      <button class="primary-button" type="submit">进入管理</button>
      <p v-if="error" class="form-error">{{ error }}</p>
    </form>

    <div v-else class="admin-comments">
      <article v-for="comment in comments" :key="comment.id" class="admin-comment glass-panel">
        <div>
          <strong>{{ comment.displayName }}</strong>
          <a :href="`mailto:${comment.email}`">{{ comment.email }}</a>
          <time :datetime="comment.createdAt">{{ new Date(comment.createdAt).toLocaleString() }}</time>
        </div>
        <p>{{ comment.content }}</p>
        <button type="button" class="danger-button" aria-label="Delete comment" @click="remove(comment.id)">
          <Trash2 :size="17" />
        </button>
      </article>
      <p v-if="!comments.length" class="empty-state glass-panel">暂无留言。</p>
    </div>
  </section>
</template>
