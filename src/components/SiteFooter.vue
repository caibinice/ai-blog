<script setup lang="ts">
import { Github, Rss } from 'lucide-vue-next'
</script>

<template>
  <footer class="site-footer">
    <div>
      <strong>Fish</strong>
      <span>Building evidence, not just demos.</span>
    </div>
    <div class="footer-links">
      <a href="https://github.com/caibinice" target="_blank" rel="noreferrer" aria-label="GitHub">
        <Github :size="18" />
      </a>
      <a href="https://my.oschina.net/caibinice" target="_blank" rel="noreferrer" aria-label="OSChina">
        <Rss :size="18" />
      </a>
      <span>© 2026 caibinice</span>
    </div>
  </footer>
</template>
