rec {
  cpuSlots = 4;
  cpuQuota = "${toString (cpuSlots * 100)}%";
  memoryMax = "24G";
  tasksMax = 4096;
}
