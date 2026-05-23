//! Emits one JSON snapshot per line (NDJSON) for Quickshell SystemMonitorService.
//! No config files; degrades gracefully when GPU/sensors are unavailable.

use serde::Serialize;
use std::{
    fs,
    net::Ipv4Addr,
    path::Path,
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};

const DEFAULT_INTERVAL_MS: u64 = 2000;
const AVG_SAMPLES: usize = 30;
const ONCE_CPU_WARMUP_MS: u64 = 350;

fn main() {
    let mut args = std::env::args().skip(1);
    let mut once = false;
    let mut interval_ms = DEFAULT_INTERVAL_MS;
    while let Some(a) = args.next() {
        match a.as_str() {
            "--once" => once = true,
            "--interval-ms" => {
                interval_ms = args
                    .next()
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(DEFAULT_INTERVAL_MS);
            }
            "--help" | "-h" => {
                eprintln!(
                    "usage: cloudyy-system-monitor [--once] [--interval-ms MS]\n\
                     Prints one JSON object per line to stdout."
                );
                return;
            }
            _ => {}
        }
    }

    let mut state = Collector::new();
    if once {
        // --once is a new process each poll: use cache if present, else warmup /proc/stat.
        if state.cpu_prev.is_none() {
            let _ = state.sample();
            thread::sleep(Duration::from_millis(ONCE_CPU_WARMUP_MS));
        }
        print_snapshot(&state.sample());
        return;
    }

    loop {
        print_snapshot(&state.sample());
        thread::sleep(Duration::from_millis(interval_ms));
    }
}

fn print_snapshot(snap: &Snapshot) {
    let line = match serde_json::to_string(snap) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("cloudyy-system-monitor: json error: {e}");
            r#"{"error":"serialize"}"#.to_string()
        }
    };
    println!("{line}");
}

// ── JSON schema (matches docs/superpowers/specs/2026-05-21-system-overview-design.md)

#[derive(Serialize)]
struct Snapshot {
    cpu: CpuInfo,
    ram: RamInfo,
    gpu: GpuInfo,
    disks: Vec<DiskInfo>,
    network: NetworkInfo,
    sensors: Vec<SensorReading>,
    fans: Vec<FanReading>,
}

#[derive(Serialize)]
struct CpuInfo {
    percent: u8,
    avg_percent: u8,
    #[serde(skip_serializing_if = "Option::is_none")]
    temp_c: Option<u8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    freq_ghz: Option<f32>,
    model: String,
    cores: u16,
}

#[derive(Serialize)]
struct RamInfo {
    percent: u8,
    used_gb: f32,
    total_gb: f32,
    swap_used_gb: f32,
    swap_total_gb: f32,
    swap_percent: u8,
}

#[derive(Serialize)]
struct GpuInfo {
    available: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    percent: Option<u8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    power_w: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    temp_c: Option<u8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    vram_used_gb: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    vram_total_gb: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    name: Option<String>,
}

#[derive(Serialize)]
struct DiskInfo {
    mount: String,
    percent: u8,
    used_gb: f32,
    total_gb: f32,
}

#[derive(Serialize)]
struct NetworkInfo {
    iface: String,
    rx_bps: u64,
    tx_bps: u64,
    ip: String,
}

#[derive(Serialize)]
struct SensorReading {
    label: String,
    temp_c: u8,
}

#[derive(Serialize)]
struct FanReading {
    label: String,
    rpm: u32,
}

// ── Collector ─────────────────────────────────────────────────────────────────

struct Collector {
    cpu_model: String,
    cpu_cores: u16,
    cpu_prev: Option<(u64, u64)>,
    cpu_recent: Vec<u8>,
    net_prev: Option<(String, u64, u64, Instant)>,
    gpu_name_cache: Option<String>,
    state_file: Option<std::path::PathBuf>,
}

impl Collector {
    fn new() -> Self {
        let mut c = Self {
            cpu_model: read_cpu_model(),
            cpu_cores: read_cpu_cores(),
            cpu_prev: None,
            cpu_recent: Vec::new(),
            net_prev: None,
            gpu_name_cache: None,
            state_file: state_cache_path(),
        };
        c.load_cached_state();
        c
    }

    fn load_cached_state(&mut self) {
        let Some(path) = self.state_file.as_ref() else {
            return;
        };
        let Ok(data) = fs::read_to_string(path) else {
            return;
        };
        let mut cpu_total = None;
        let mut cpu_idle = None;
        let mut net_iface = String::new();
        let mut net_rx = 0u64;
        let mut net_tx = 0u64;
        let mut net_epoch_ms = 0u64;
        for line in data.lines() {
            if let Some(v) = line.strip_prefix("cpu_total=") {
                cpu_total = v.trim().parse().ok();
            } else if let Some(v) = line.strip_prefix("cpu_idle=") {
                cpu_idle = v.trim().parse().ok();
            } else if let Some(v) = line.strip_prefix("net_iface=") {
                net_iface = v.trim().to_string();
            } else if let Some(v) = line.strip_prefix("net_rx=") {
                net_rx = v.trim().parse().unwrap_or(0);
            } else if let Some(v) = line.strip_prefix("net_tx=") {
                net_tx = v.trim().parse().unwrap_or(0);
            } else if let Some(v) = line.strip_prefix("net_epoch_ms=") {
                net_epoch_ms = v.trim().parse().unwrap_or(0);
            }
        }
        if let (Some(total), Some(idle)) = (cpu_total, cpu_idle) {
            self.cpu_prev = Some((total, idle));
        }
        if !net_iface.is_empty() && net_epoch_ms > 0 {
            let age_ms = epoch_ms().saturating_sub(net_epoch_ms).min(120_000);
            let t0 = Instant::now() - Duration::from_millis(age_ms);
            self.net_prev = Some((net_iface, net_rx, net_tx, t0));
        }
    }

    fn save_cached_state(&self) {
        let Some(path) = self.state_file.as_ref() else {
            return;
        };
        let mut lines = Vec::new();
        if let Some((total, idle)) = self.cpu_prev {
            lines.push(format!("cpu_total={total}"));
            lines.push(format!("cpu_idle={idle}"));
        }
        if let Some((iface, rx, tx, _)) = &self.net_prev {
            lines.push(format!("net_iface={iface}"));
            lines.push(format!("net_rx={rx}"));
            lines.push(format!("net_tx={tx}"));
            lines.push(format!("net_epoch_ms={}", epoch_ms()));
        }
        if lines.is_empty() {
            return;
        }
        if let Some(parent) = path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let _ = fs::write(path, lines.join("\n"));
    }

    fn sample(&mut self) -> Snapshot {
        let (cpu_pct, cpu_avg) = self.read_cpu();
        let snap = Snapshot {
            cpu: CpuInfo {
                percent: cpu_pct,
                avg_percent: cpu_avg,
                temp_c: read_cpu_temp_c(),
                freq_ghz: read_cpu_freq_ghz(),
                model: self.cpu_model.clone(),
                cores: self.cpu_cores,
            },
            ram: read_ram(),
            gpu: read_gpu(&mut self.gpu_name_cache),
            disks: read_disks(),
            network: self.read_network(),
            sensors: read_thermal_sensors(),
            fans: read_fans(),
        };
        self.save_cached_state();
        snap
    }

    fn read_cpu(&mut self) -> (u8, u8) {
        let Some((total, idle)) = parse_proc_stat() else {
            return (0, rolling_avg(&self.cpu_recent));
        };
        let pct = match self.cpu_prev {
            Some((pt, pi)) if total > pt => {
                let dt = total - pt;
                let di = idle.saturating_sub(pi);
                pct_u8((dt.saturating_sub(di)) as f64 / dt as f64 * 100.0)
            }
            _ => 0,
        };
        self.cpu_prev = Some((total, idle));
        push_recent(&mut self.cpu_recent, pct);
        (pct, rolling_avg(&self.cpu_recent))
    }

    fn read_network(&mut self) -> NetworkInfo {
        let (iface, ip) = default_iface_and_ip();
        let (rx, tx) = iface_byte_counters(&iface);
        let now = Instant::now();
        let (rx_bps, tx_bps) = match self.net_prev.take() {
            Some((prev_if, prx, ptx, t0)) if prev_if == iface => {
                let secs = now.duration_since(t0).as_secs_f64().max(0.001);
                let drx = rx.saturating_sub(prx) as f64 / secs;
                let dtx = tx.saturating_sub(ptx) as f64 / secs;
                self.net_prev = Some((iface.clone(), rx, tx, now));
                (drx as u64, dtx as u64)
            }
            _ => {
                self.net_prev = Some((iface.clone(), rx, tx, now));
                (0, 0)
            }
        };
        NetworkInfo {
            iface,
            rx_bps,
            tx_bps,
            ip,
        }
    }
}

fn epoch_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn state_cache_path() -> Option<std::path::PathBuf> {
    if let Ok(p) = std::env::var("XDG_CACHE_HOME") {
        return Some(std::path::PathBuf::from(p).join("cloudyy/system-monitor.state"));
    }
    std::env::var("HOME")
        .ok()
        .map(|h| std::path::PathBuf::from(h).join(".cache/cloudyy/system-monitor.state"))
}

fn pct_u8(v: f64) -> u8 {
    v.clamp(0.0, 100.0).round() as u8
}

fn push_recent(buf: &mut Vec<u8>, v: u8) {
    if buf.len() >= AVG_SAMPLES {
        buf.remove(0);
    }
    buf.push(v);
}

fn rolling_avg(buf: &[u8]) -> u8 {
    if buf.is_empty() {
        return 0;
    }
    let s: u32 = buf.iter().map(|&x| x as u32).sum();
    (s / buf.len() as u32) as u8
}

fn parse_proc_stat() -> Option<(u64, u64)> {
    let line = fs::read_to_string("/proc/stat").ok()?;
    let cpu = line.lines().next()?;
    let parts = cpu.split_whitespace().skip(1);
    let mut total = 0u64;
    let mut idle = 0u64;
    for (i, p) in parts.enumerate() {
        let v: u64 = p.parse().ok()?;
        total += v;
        if i == 3 {
            idle = v;
        } else if i == 4 {
            idle += v; // iowait
        }
    }
    if total == 0 {
        return None;
    }
    Some((total, idle))
}

fn read_cpu_model() -> String {
    let Ok(data) = fs::read_to_string("/proc/cpuinfo") else {
        return String::from("CPU");
    };
    for line in data.lines() {
        if let Some((_k, v)) = line.split_once(':') {
            if line.to_lowercase().starts_with("model name") {
                let name = v.trim();
                let short = name.split('@').next().unwrap_or(name).trim();
                return short.to_string();
            }
        }
    }
    String::from("CPU")
}

fn read_cpu_cores() -> u16 {
    fs::read_to_string("/proc/cpuinfo")
        .map(|d| d.lines().filter(|l| l.starts_with("processor")).count() as u16)
        .unwrap_or(1)
        .max(1)
}

fn read_cpu_temp_c() -> Option<u8> {
    thermal_zone_temp("x86_pkg_temp")
        .or_else(|| thermal_zone_temp("tctl"))
        .or_else(|| thermal_zone_temp("cpu-thermal"))
        .or_else(|| {
            fs::read_dir("/sys/class/thermal")
                .ok()?
                .filter_map(|e| e.ok())
                .filter_map(|e| {
                    let p = e.path();
                    if p.file_name()?.to_string_lossy().starts_with("thermal_zone") {
                        temp_milli_c(&p.join("temp"))
                    } else {
                        None
                    }
                })
                .max()
        })
}

fn thermal_zone_temp(typ: &str) -> Option<u8> {
    let base = Path::new("/sys/class/thermal");
    let entries = fs::read_dir(base).ok()?;
    for e in entries.filter_map(|e| e.ok()) {
        let p = e.path();
        let t = fs::read_to_string(p.join("type")).unwrap_or_default();
        if t.trim() == typ {
            return temp_milli_c(&p.join("temp"));
        }
    }
    None
}

fn temp_milli_c(path: &Path) -> Option<u8> {
    let raw: i64 = fs::read_to_string(path).ok()?.trim().parse().ok()?;
    let c = raw / 1000;
    if (10..=120).contains(&c) {
        Some(c as u8)
    } else {
        None
    }
}

fn read_cpu_freq_ghz() -> Option<f32> {
    let base = Path::new("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq");
    let khz: u64 = fs::read_to_string(base).ok()?.trim().parse().ok()?;
    Some((khz as f32 / 1_000_000.0 * 10.0).round() / 10.0)
}

fn read_ram() -> RamInfo {
    let mut mem_total_kb = 0u64;
    let mut mem_avail_kb = 0u64;
    let mut swap_total_kb = 0u64;
    let mut swap_free_kb = 0u64;
    if let Ok(data) = fs::read_to_string("/proc/meminfo") {
        for line in data.lines() {
            let Some((k, v)) = line.split_once(':') else {
                continue;
            };
            let kb: u64 = v.split_whitespace().next().and_then(|s| s.parse().ok()).unwrap_or(0);
            match k.trim() {
                "MemTotal" => mem_total_kb = kb,
                "MemAvailable" => mem_avail_kb = kb,
                "SwapTotal" => swap_total_kb = kb,
                "SwapFree" => swap_free_kb = kb,
                _ => {}
            }
        }
    }
    let used_kb = mem_total_kb.saturating_sub(mem_avail_kb);
    let swap_used_kb = swap_total_kb.saturating_sub(swap_free_kb);
    let total_gb = kb_to_gb(mem_total_kb);
    let used_gb = kb_to_gb(used_kb);
    let swap_total_gb = kb_to_gb(swap_total_kb);
    let swap_used_gb = kb_to_gb(swap_used_kb);
    RamInfo {
        percent: pct_u8(used_kb as f64 / mem_total_kb.max(1) as f64 * 100.0),
        used_gb,
        total_gb,
        swap_used_gb,
        swap_total_gb,
        swap_percent: pct_u8(swap_used_kb as f64 / swap_total_kb.max(1) as f64 * 100.0),
    }
}

fn kb_to_gb(kb: u64) -> f32 {
    ((kb as f64 / 1_048_576.0) * 10.0).round() as f32 / 10.0
}

fn read_gpu(name_cache: &mut Option<String>) -> GpuInfo {
    let out = Command::new("nvidia-smi")
        .args([
            "--query-gpu=utilization.gpu,temperature.gpu,power.draw,memory.used,memory.total,name",
            "--format=csv,noheader,nounits",
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output();
    let Ok(out) = out else {
        return gpu_unavailable();
    };
    if !out.status.success() {
        return gpu_unavailable();
    }
    let line = String::from_utf8_lossy(&out.stdout);
    let line = line.lines().next().unwrap_or("").trim();
    let mut parts = line.split(',').map(str::trim);
    let util: u8 = parts.next().and_then(|s| s.parse().ok()).unwrap_or(0);
    let temp: Option<u8> = parts.next().and_then(|s| s.parse::<f32>().ok()).map(|t| t.round() as u8);
    let power: Option<u16> = parts.next().and_then(|s| s.parse::<f32>().ok()).map(|p| p.round() as u16);
    let vram_used_mb: f32 = parts.next().and_then(|s| s.parse().ok()).unwrap_or(0.0);
    let vram_total_mb: f32 = parts.next().and_then(|s| s.parse().ok()).unwrap_or(0.0);
    let name: String = parts.next().unwrap_or("GPU").to_string();
    *name_cache = Some(name.clone());
    GpuInfo {
        available: true,
        percent: Some(util.min(100)),
        power_w: power,
        temp_c: temp,
        vram_used_gb: Some((vram_used_mb / 1024.0 * 10.0).round() / 10.0),
        vram_total_gb: Some((vram_total_mb / 1024.0 * 10.0).round() / 10.0),
        name: Some(name),
    }
}

fn gpu_unavailable() -> GpuInfo {
    GpuInfo {
        available: false,
        percent: None,
        power_w: None,
        temp_c: None,
        vram_used_gb: None,
        vram_total_gb: None,
        name: None,
    }
}

fn read_disks() -> Vec<DiskInfo> {
    let out = Command::new("df")
        .args(["-PT", "-B1"])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output();
    let Ok(out) = out else {
        return Vec::new();
    };
    if !out.status.success() {
        return Vec::new();
    }
    let mut disks = Vec::new();
    let text = String::from_utf8_lossy(&out.stdout);
    for line in text.lines().skip(1) {
        let mut cols = line.split_whitespace();
        let _dev = cols.next();
        let fstype = cols.next().unwrap_or("");
        let _size = cols.next();
        let used = cols.next().and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
        let _avail = cols.next();
        let pct_str = cols.next().unwrap_or("0%");
        let mount = cols.next().unwrap_or("").to_string();
        if mount.is_empty() || !is_real_mount(fstype, &mount) {
            continue;
        }
        let percent = pct_str.trim_end_matches('%').parse::<u8>().unwrap_or(0);
        let total = used.saturating_mul(100).saturating_div(percent.max(1) as u64);
        disks.push(DiskInfo {
            mount,
            percent,
            used_gb: bytes_to_gb(used),
            total_gb: bytes_to_gb(total),
        });
    }
    disks.sort_by(|a, b| a.mount.cmp(&b.mount));
    disks
}

fn is_real_mount(fstype: &str, mount: &str) -> bool {
    const SKIP_FS: &[&str] = &[
        "tmpfs", "devtmpfs", "devfs", "squashfs", "overlay", "efivarfs", "autofs", "proc", "sysfs",
    ];
    if SKIP_FS.contains(&fstype) {
        return false;
    }
    if mount.starts_with("/dev/") || mount == "/dev" {
        return false;
    }
    if mount.starts_with("/run/user") || mount.starts_with("/proc") || mount.starts_with("/sys") {
        return false;
    }
    mount == "/" || mount.starts_with("/home") || mount.starts_with("/boot") || mount.starts_with("/mnt")
}

fn bytes_to_gb(b: u64) -> f32 {
    ((b as f64 / 1_073_741_824.0) * 10.0).round() as f32 / 10.0
}

fn default_iface_and_ip() -> (String, String) {
    let data = fs::read_to_string("/proc/net/route").unwrap_or_default();
    let mut best_iface = String::from("lo");
    let mut best_metric = u32::MAX;
    for line in data.lines().skip(1) {
        let mut c = line.split_whitespace();
        let iface = c.next().unwrap_or("");
        let dest = c.next().unwrap_or("");
        let _gw = c.next();
        let flags = c.next().unwrap_or("");
        let _refcnt = c.next();
        let _use = c.next();
        let metric = c.next().and_then(|s| s.parse().ok()).unwrap_or(0u32);
        if dest == "00000000" && flags == "0003" && metric <= best_metric {
            best_metric = metric;
            best_iface = iface.to_string();
        }
    }
    let ip = iface_ipv4(&best_iface).unwrap_or_else(|| String::from(""));
    (best_iface, ip)
}

fn iface_ipv4(iface: &str) -> Option<String> {
    let out = Command::new("ip")
        .args(["-4", "-o", "addr", "show", "dev", iface])
        .stdout(Stdio::piped())
        .output()
        .ok()?;
    let line = String::from_utf8_lossy(&out.stdout);
    for token in line.split_whitespace() {
        if token.contains('.') && token.contains('/') {
            let ip = token.split('/').next()?;
            if ip.parse::<Ipv4Addr>().is_ok() {
                return Some(ip.to_string());
            }
        }
    }
    None
}

fn iface_byte_counters(iface: &str) -> (u64, u64) {
    let rx = fs::read_to_string(format!("/sys/class/net/{iface}/statistics/rx_bytes"))
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);
    let tx = fs::read_to_string(format!("/sys/class/net/{iface}/statistics/tx_bytes"))
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);
    (rx, tx)
}

fn read_thermal_sensors() -> Vec<SensorReading> {
    let mut out = Vec::new();
    let base = Path::new("/sys/class/hwmon");
    let Ok(entries) = fs::read_dir(base) else {
        return out;
    };
    for entry in entries.filter_map(|e| e.ok()) {
        let dir = entry.path();
        let label = fs::read_to_string(dir.join("name"))
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|_| "sensor".into());
        let Ok(files) = fs::read_dir(&dir) else {
            continue;
        };
        for f in files.filter_map(|e| e.ok()) {
            let fname = f.file_name().to_string_lossy().to_string();
            if fname.starts_with("temp") && fname.ends_with("_input") {
                if let Some(t) = temp_milli_c(&f.path()) {
                    out.push(SensorReading {
                        label: label.clone(),
                        temp_c: t,
                    });
                    break;
                }
            }
        }
    }
    out.truncate(8);
    out
}

fn read_fans() -> Vec<FanReading> {
    let mut out = Vec::new();
    let base = Path::new("/sys/class/hwmon");
    let Ok(entries) = fs::read_dir(base) else {
        return out;
    };
    for entry in entries.filter_map(|e| e.ok()) {
        let dir = entry.path();
        let label = fs::read_to_string(dir.join("name"))
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|_| "fan".into());
        let Ok(files) = fs::read_dir(&dir) else {
            continue;
        };
        for f in files.filter_map(|e| e.ok()) {
            let fname = f.file_name().to_string_lossy().to_string();
            if fname.starts_with("fan") && fname.ends_with("_input") {
                if let Ok(rpm) = fs::read_to_string(f.path()).and_then(|s| {
                    s.trim()
                        .parse::<u32>()
                        .map_err(|_| std::io::Error::other("parse"))
                }) {
                    if rpm > 0 && rpm < 50_000 {
                        out.push(FanReading { label, rpm });
                        break;
                    }
                }
            }
        }
    }
    out.truncate(4);
    out
}
