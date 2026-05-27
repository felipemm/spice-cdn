// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

const site = process.env.PUBLIC_ASTRO_SITE || 'http://localhost:4321';
const base = process.env.PUBLIC_ASTRO_BASE || '/';

// https://astro.build/config
export default defineConfig({
	site,
	base,
	integrations: [
		starlight({
			title: 'Spice CDN Platform',
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/felipemm/spice-cdn' }],
			sidebar: [
				{
					label: 'Guides',
					items: [
						{ label: 'User guide', slug: 'guides/user-guide' },
						{ label: 'Install', slug: 'guides/install' },
						{ label: 'Product vs GitOps', slug: 'guides/architecture' },
					],
				},
				{
					label: 'Reference',
					items: [{ autogenerate: { directory: 'reference' } }],
				},
			],
		}),
	],
});
