# /guide

Interactive step-by-step guide for nvim plugin development tasks.

## Instructions

1. Ask the user what they want to accomplish. Gather enough context to build a
   step-by-step plan (the plugin name, the goal, any constraints).

2. Determine the plugin name from the current repo (basename of the working
   directory) and today's date. Run exactly one Bash command:

   ```
   basename "$(git rev-parse --show-toplevel)" && date +%Y-%m-%d
   ```

3. Build a numbered step-by-step plan as a markdown file. Run exactly one Bash
   command:

   ```
   mkdir -p /tmp/<plugin>-<date> && cat > /tmp/<plugin>-<date>/guide.md <<'EOF'
   # <Goal>

   Plugin: <plugin>
   Date: <date>
   Branch: <branch name to create>

   ## Steps

   1. <step>
   2. <step>
   ...

   ## Current

   Step 1: <description>
   EOF
   ```

4. Present step 1 to the user. Execute it. Show the result. Ask for
   confirmation before moving to the next step.

5. After the user confirms, update the `## Current` section in the guide to
   reflect the next step, then execute it. Repeat until all steps are done.

6. When all steps are complete, update the guide with a `## Done` section and
   print the path to the guide file.

Keep each step small and self-contained. Prefer one logical change per step.
If a step reveals unexpected complexity, break it into sub-steps and update
the guide before proceeding.
