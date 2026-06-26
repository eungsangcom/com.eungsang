module.exports = {
  options: {
    doNotFollow: {
      path: 'node_modules'
    },
    exclude: {
      path: '(^node_modules$|^flutter_SDK$)'
    },
    tsConfig: {
      fileName: 'tsconfig.json'
    }
  },
  forbidden: [
    {
      name: 'hub-spoke-restriction',
      comment: 'apps/* should not import from other apps/* directly; use apps/star_craft as the hub.',
      severity: 'error',
      from: {
        path: '^eungsang/apps/(?!star_craft)/'
      },
      to: {
        path: '^eungsang/apps/(?!star_craft)/'
      }
    }
  ]
};
