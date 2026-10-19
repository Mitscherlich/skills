#!/usr/bin/awk -f
# Acpus 并行子图的结构检查；语义独立性由计划审阅核对。
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function fail(s) { print "fail=P-acpus: " s; errors++ }
BEGIN { FS="|" }
/^acpus_(max_parallel|max_attempts|task_timeout_minutes|run_timeout_minutes):/ {
  key=$0; sub(/:.*/, "", key)
  value=$0; sub(/^[^:]*:[[:space:]]*/, "", value); value=trim(value)
  count[key]++
  if (value !~ /^[1-9][0-9]*$/) fail(key " 必须为正整数")
}
/^\|[[:space:]]*F[0-9]+[[:space:]]*\|/ {
  f=trim($2); slices[f]=trim($4)
}
/^\|[[:space:]]*T[0-9]+[[:space:]]*\|/ {
  t=trim($2)
  if (t in tasks) fail("重复子任务 " t)
  tasks[t]=trim($3); dependencies[t]=trim($4)
  if (trim($5)=="" || trim($6)=="" || dependencies[t]=="") fail(t " 缺依赖、写入边界或验收命令")
}
END {
  n=split("acpus_max_parallel acpus_max_attempts acpus_task_timeout_minutes acpus_run_timeout_minutes", keys, " ")
  for (i=1;i<=n;i++) if (count[keys[i]]!=1) fail(keys[i] " 必须声明一次")
  total=0
  for (t in tasks) {
    total++; coverage[tasks[t]]++
    if (!(tasks[t] in slices)) fail(t " 引用未知切片 " tasks[t])
    if (dependencies[t]=="-") continue
    n=split(dependencies[t], ds, ",")
    for (i=1;i<=n;i++) {
      d=trim(ds[i])
      if (!(d in tasks)) { fail(t " 引用未知依赖 " d); continue }
      if (tasks[d]!=tasks[t]) fail(t " 跨切片依赖；切片间由 roadmap 顺序承接")
      if (!((d SUBSEP t) in edges)) { edges[d,t]=1; degree[t]++ }
    }
  }
  if (total==0) fail("至少需要一条 T<n> 子任务")
  for (f in slices) if (slices[f] !~ /^paused/ && coverage[f]==0) fail(f " 缺少子任务")
  # 拓扑消除：依赖顺序可与表格顺序不同。
  completed=0
  do {
    changed=0
    for (t in tasks) if (!(t in removed) && degree[t]==0) {
      removed[t]=1; completed++; changed=1
      for (v in tasks) if ((t SUBSEP v) in edges) degree[v]--
    }
  } while (changed)
  if (completed!=total) fail("子任务存在循环依赖")
  exit(errors ? 1 : 0)
}
