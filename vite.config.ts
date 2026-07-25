import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  build: {
    sourcemap: false,
    target: 'es2020',
    cssCodeSplit: true,
    rollupOptions: {
      output: {
        entryFileNames: 'assets/app-[hash].js',
        chunkFileNames: (chunk) => {
          const name = chunk.name || 'chunk'
          return name.startsWith('vendor') ? 'assets/vendor-[name]-[hash].js' : 'assets/chunk-[name]-[hash].js'
        },
        assetFileNames: 'assets/[name]-[hash][extname]',
        manualChunks(id) {
          if (!id.includes('node_modules')) return undefined
          if (id.includes('motion-v')) return 'vendor-motion'
          if (id.includes('markdown-it')) return 'vendor-markdown'
          if (id.includes('lucide-vue-next')) return 'vendor-icons'
          if (id.includes('vue') || id.includes('@unhead')) return 'vendor-vue'
          return 'vendor-misc'
        },
      },
    },
  },
  ssgOptions: {
    script: 'async',
    formatting: 'minify',
  },
})
