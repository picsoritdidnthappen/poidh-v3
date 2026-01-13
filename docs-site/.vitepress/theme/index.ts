import Theme from 'vitepress/theme'
import './custom.css'
import type { EnhanceAppContext } from 'vitepress'

export default {
  ...Theme,
  enhanceApp(ctx: EnhanceAppContext) {
    Theme.enhanceApp?.(ctx)
  }
}
