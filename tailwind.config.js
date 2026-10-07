/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        carbon: {
          DEFAULT: '#242424',
          dark: '#181818',
          light: '#3a3a3a',
          muted: '#525252',
        },
        turquesa: {
          DEFAULT: '#01CFCB',
          hover: '#00b8b4',
          dark: '#007a77',
          light: '#5ce1df',
        },
        claro: {
          DEFAULT: '#D8FAF9',
          surface: '#f0fdfc',
        },
        alerta: {
          DEFAULT: '#D9644A',
          hover: '#c2533b',
          bg: '#fff5f3',
          dark: '#a8412b',
        },
        borde: '#e5e7eb',
      },
    },
  },
  plugins: [],
}
