module.exports = {
  root: true,
  parser: '@typescript-eslint/parser',
  plugins: ['@typescript-eslint'],
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
    'plugin:prettier/recommended'  // Enables eslint-plugin-prettier and displays prettier errors as ESLint errors.
  ],
  rules: {
    // Add your tight rules here
    '@typescript-eslint/explicit-function-return-type': 'error',
  },
};