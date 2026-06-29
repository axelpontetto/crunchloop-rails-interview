# By default Rails wraps form fields that have validation errors in
# <div class="field_with_errors">. That extra block-level wrapper breaks our
# flex layouts (e.g. the add-todo input loses its `flex-1` and collapses to its
# default width when the form re-renders with errors). Render the field inline
# instead, leaving error messaging to the explicit error banner in the form.
Rails.application.config.action_view.field_error_proc = proc { |html_tag, _instance| html_tag.html_safe }
