#!/bin/bash

any_issues=false

if [[ $# -gt 0 ]]; then
    targets=("$@")
else
    mapfile -t targets < <(find tools -name '*.py')
fi

for file in "${targets[@]}"; do
    [[ -f $file && $file == *.py ]] || continue

    # Run tools and capture output
    pylint_output=$(pylint --errors-only "$file" 2>&1 || true)
    black_output=$(black --check --diff --quiet "$file" 2>&1 || true)

    # Check if there were issues
    if [[ -n "$pylint_output" || "$black_output" == *"would reformat"* ]]; then
        if ! $any_issues; then
            echo "## :x: Python Checks Failed"
            any_issues=true
        fi

        if [[ -n "$pylint_output" ]]; then
            echo "#### Pylint Errors:"
            echo "> $file"
            echo '```'
            echo "$pylint_output"
            echo '```'
            echo
        fi
        if [[ -n "$black_output" ]]; then
            echo "#### Formatting Errors:"
            echo "> $file"
            echo '```diff'
            echo "$black_output"
            echo '```'
            echo
        fi
    fi
done

for file in "${targets[@]}"; do
    if [[ $file == tools/mochirii/client_graphics_audit.py ||
          $file == tools/mochirii/trust_parity_audit.py ||
          $file == tools/mochirii/tests/test_*.py ||
          $file == tools/mochirii/tests/fixtures/trust_parity/* ||
          $file == restore/manifests/client-graphics-gates.manifest.json ]]; then
        if ! unittest_output=$(python -m unittest discover -s tools/mochirii/tests -p 'test_*.py' 2>&1); then
            if ! $any_issues; then
                echo "## :x: Python Checks Failed"
                any_issues=true
            fi
            echo "#### Mochirii Tool Tests:"
            echo '```'
            echo "$unittest_output"
            echo '```'
            echo
        fi
        break
    fi
done

$any_issues && exit 1 || exit 0
