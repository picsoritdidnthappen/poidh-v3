import { defineConfig } from 'vitepress'

export default defineConfig({
  ignoreDeadLinks: true, 
  
  title: 'poidh docs',
  description: 'Secure bounty protocol with social crowdfunding, weighted polling, and pull-payments',

  themeConfig: {
    nav: [
      { text: 'home', link: '/' },
      { text: 'start here', link: '/start-here/what-is-poidh' },
      { text: 'developers', link: '/developers/building-on-poidh' },
      { text: 'contracts', link: '/contracts/overview' }
    ],

    sidebar: [
      {
        text: 'start here',
        collapsed: false,
        items: [
          { text: 'what is poidh?', link: '/start-here/what-is-poidh' },
          { text: 'how poidh works', link: '/start-here/how-it-works' }
        ]
      },
      {
        text: 'using poidh',
        collapsed: false,
        items: [
          { text: 'boosting a bounty', link: '/using-poidh/boosting-a-bounty' },
          { text: 'claiming a bounty', link: '/using-poidh/claiming-a-bounty' },
          { text: 'confirming a claim', link: '/using-poidh/confirming-a-claim' },
          { text: 'creating a bounty', link: '/using-poidh/creating-a-bounty' },
          { text: 'getting paid', link: '/using-poidh/getting-paid' },
          { text: 'voting on claims', link: '/using-poidh/voting-on-claims' }
        ]
      },
      {
        text: 'features',
        collapsed: false,
        items: [
          { text: 'albums', link: '/features/albums' },
          { text: 'claim nfts', link: '/features/claim-nfts' },
          { text: 'poidh score', link: '/features/poidh-score' },
          { text: 'profiles', link: '/features/profiles' }
        ]
      },
      {
        text: 'developers',
        collapsed: false,
        items: [
          { text: 'building on poidh', link: '/developers/building-on-poidh' },
          { text: 'alternate frontends', link: '/developers/alternate-frontends' }
        ]
      },
      {
        text: 'contracts',
        collapsed: false,
        items: [
          { text: 'overview', link: '/contracts/overview' },
          { text: 'architecture', link: '/contracts/architecture' },
          { text: 'state machines', link: '/contracts/state-machines' },
          { text: 'security', link: '/contracts/security' },
          { text: 'api reference', link: '/contracts/api' },
          { text: 'deployment', link: '/contracts/deployment' }
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
