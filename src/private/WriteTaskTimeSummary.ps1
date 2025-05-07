function WriteTaskTimeSummary($invokePsakeDuration) {
    if ($psake.context.Count -gt 0) {
        $currentContext = $psake.context.Peek()

        if ($currentContext.config.taskNameFormat -is [ScriptBlock]) {
            & $currentContext.config.taskNameFormat "Execution Time Report"
        } elseif ($currentContext.config.taskNameFormat -ne "Executing {0}") {
            $currentContext.config.taskNameFormat -f "Execution Time Report"
        } else {
            WriteOutput ("-" * 70)
            WriteOutput "Execution Time Report"
            WriteOutput ("-" * 70)
        }

        $taskMap = @{}
        $dependencyMap = @{}
        $executedTaskNames = @()

        while ($currentContext.executedTasks.Count -gt 0) {
            $taskKey = $currentContext.executedTasks.Pop()
            if ($taskKey -eq "default") { continue }

            $task = $currentContext.tasks.$taskKey
            $taskMap[$taskKey] = $task
            $dependencyMap[$taskKey] = $task.Preconditions | ForEach-Object { $_.TaskName }
            $executedTaskNames += $taskKey
        }

        # Reverse the list to maintain order
        [Array]::Reverse($executedTaskNames)

        if ($currentContext.config.enhancedTaskSummary) {

            function Get-InclusiveDuration {
                param (
                    [string]$taskName,
                    [ref]$visited
                )
                if ($visited.Value -contains $taskName) { return [TimeSpan]::Zero }
                $visited.Value += $taskName

                $duration = $taskMap[$taskName].Duration
                foreach ($dep in $dependencyMap[$taskName]) {
                    if ($taskMap.ContainsKey($dep)) {
                        $duration += Get-InclusiveDuration -taskName $dep -visited $visited
                    }
                }
                return $duration
            }

            function Print-TaskTree {
                param (
                    [string]$taskName,
                    [string]$prefix = "",
                    [bool]$isLast = $true
                )
                $children = $dependencyMap[$taskName]
                $exclusive = $taskMap[$taskName].Duration
                $visited = [ref]@()
                $inclusive = Get-InclusiveDuration -taskName $taskName -visited $visited

                $branch = if ($prefix -eq "") { "" }
                          elseif ($isLast) { "╚═ " }
                          else { "╠═ " }

                $line = "{0}{1,-30} {2,-16} {3,-16}" -f $prefix, $branch + $taskName, $exclusive.ToString("hh\:mm\:ss\.fff"), $inclusive.ToString("hh\:mm\:ss\.fff")
                WriteOutput $line

                for ($i = 0; $i -lt $children.Count; $i++) {
                    $child = $children[$i]
                    if (-not $taskMap.ContainsKey($child)) { continue }
                    $isLastChild = $i -eq ($children.Count - 1)
                    $newPrefix = $prefix + (if ($prefix -eq "") { "" } elseif ($isLast) { "   " } else { "║  " })
                    Print-TaskTree -taskName $child -prefix $newPrefix -isLast:$isLastChild
                }
            }

            WriteOutput ("{0,-35} {1,-16} {2,-16}" -f "Name", "Duration excl.", "Duration incl.")
            WriteOutput ("{0,-35} {1,-16} {2,-16}" -f "----", "--------------", "--------------")

            $allDeps = $dependencyMap.Values | Select-Object -ExpandProperty *
            $roots = $executedTaskNames | Where-Object { $allDeps -notcontains $_ }

            foreach ($root in $roots) {
                Print-TaskTree -taskName $root
            }

            WriteOutput ("{0,-35} {1,-16}" -f "Total:", $invokePsakeDuration.ToString("hh\:mm\:ss\.fff"))

        } else {
            # Fallback to original flat summary
            $list = @()
            foreach ($taskKey in $executedTaskNames) {
                $task = $taskMap[$taskKey]
                $list += [PSCustomObject]@{
                    Name     = $task.Name
                    Duration = $task.Duration.ToString("hh\:mm\:ss\.fff")
                }
            }
            $list += [PSCustomObject]@{
                Name     = "Total:"
                Duration = $invokePsakeDuration.ToString("hh\:mm\:ss\.fff")
            }

            $list | Format-Table -AutoSize -Property Name, Duration | Out-String -Stream | Where-Object { $_ } | WriteOutput
        }
    }
}
