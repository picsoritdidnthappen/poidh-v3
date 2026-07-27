import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'poidh docs',
  description: 'Secure bounty protocol with social crowdfunding, weighted polling, and pull-payments',
  
    themeConfig: {
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Start Here', link: '/start-here/what-is-poidh' },
      { text: 'Developers', link: '/developers/index' },
    ],

    sidebar: [
      {
        text: 'Start Here',
        items: [
          { text: 'What is POIDH?', link: '/start-here/what-is-poidh' },
          { text: 'How POIDH Works', link: '/start-here/how-poidh-works' },
          { text: 'Coordination Protocol', link: '/start-here/coordination-protocol' },
        ]
      },
      {
        text: 'Developers',
        items: [
          { text: 'Overview', link: '/developers/overview' },
          { text: 'Architecture', link: '/developers/architecture' },
          { text: 'State Machines', link: '/developers/state-machines' },
          { text: 'Security', link: '/developers/security' },
          { text: 'API Reference', link: '/developers/api' },
          { text: 'Deployment', link: '/developers/deployment' },
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
