module.exports = {
  overrides: [
    {
      files: "*.ts",
      options: {
        printWidth: 120,
        semi: true,
        singleQuote: true,
        trailingComma: "es5",
      },
    },
    {
      files: "*.sol",
      options: {
        printWidth: 120,
        tabWidth: 4,
        useTabs: false,
        singleQuote: false,
        bracketSpacing: false,
        explicitTypes: "always",
      },
    },
  ],
};
