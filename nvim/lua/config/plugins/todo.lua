return {
  "folke/todo-comments.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    merge_keywords = false,
    keywords = {
      TODO = { icon = " ", color = "info" },
    },
  }
}
