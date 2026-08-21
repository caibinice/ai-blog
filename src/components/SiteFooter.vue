<script setup lang="ts">
import { Github, Rss } from 'lucide-vue-next'
import { useLocale } from '../lib/useLocale'

const { t } = useLocale()
</script>

<template>
  <footer class="site-footer">
    <div class="footer-main">
      <div class="footer-intro">
        <strong>{{ t.brand }}</strong>
        <span>{{ t.footerTagline }}</span>
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
    </div>
    <a class="icp-record" href="https://beian.miit.gov.cn/" target="_blank" rel="noopener noreferrer">
      苏ICP备2026058905号-1
    </a>
  </footer>
</template>
