return {
    cmd = { 'bazel-language-server', 'server' },
    filetypes = { 'bazelrc', 'bzl', 'starlark' },
    root_markers = {
        'MODULE.bazel',
        'WORKSPACE.bazel',
        'WORKSPACE.bzlmod',
        'WORKSPACE',
        'REPO.bazel',
        '.bazelversion',
    },
    workspace_required = false,
}
