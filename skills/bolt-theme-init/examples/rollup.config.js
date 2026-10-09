const typescript = require('@rollup/plugin-typescript');
const terser = require('@rollup/plugin-terser');
const { nodeResolve } = require('@rollup/plugin-node-resolve');

module.exports = {
  input: 'js/src/index.ts',
  output: {
    file: 'js/app.js',
    format: 'iife',
    sourcemap: false,
  },
  plugins: [
    nodeResolve(),
    typescript(),
    terser(),
  ],
};
