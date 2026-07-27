import { defineConfig } from 'vitepress'

export default defineConfig({
  ignoreDeadLinks: true, 
  
  title: 'poidh docs',
  description: 'Secure bounty protocol with social crowdfunding, weighted polling, and pull-payments',
  
    themeConfig: {
    nav: [
      { text: 'home', link: '/' },
      { text: 'start here', link: '/start-here/what-is-poidh' },
      { text: 'developers', link: '/developers/overview' },
    ],

    sidebar: [
      {
        text: 'start here',
        items: [
          { text: 'what is poidh?', link: '/start-here/what-is-poidh' },
          { text: 'how poidh works', link: '/start-here/how-poidh-works' },
        ]
      },
      {
        text: 'developers',
        items: [
          { text: 'overview', link: '/developers/overview' },
          { text: 'achitecture', link: '/developers/architecture' },
          { text: 'state machines', link: '/developers/state-machines' },
          { text: 'security', link: '/developers/security' },
          { text: 'API reference', link: '/developers/api' },
          { text: 'deployment', link: '/developers/deployment' },
        ]
      }
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/picsoritdidnthappen/poidh-app' }
    ],

    search: {
      provider: 'local'
    }
  },

  head: [
    ['script', { src: 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js' }]
  ],

  markdown: {
    theme: {
      light: 'github-light',
      dark: 'github-dark'
    }
  },

  vite: {
    css: {
      preprocessorOptions: {
        scss: {
          additionalData: `
            :root {
              --vp-c-brand-1: #6366f1;
              --vp-c-brand-2: #818cf8;
              --vp-home-hero-name-background: linear-gradient(120deg, #6366f1 0%, #818cf8 100%);
            }
          `
        }
      }
    }
  }
})
