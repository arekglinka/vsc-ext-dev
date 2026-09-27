//! Force simulation for the Purs Graphs **fluent panel**.
//!
//! Compiled to `wasm32-unknown-unknown` with zero dependencies (no
//! wasm-bindgen, no allocator): the PureScript webview drives the engine
//! frame-by-frame (`step`) and reads node positions back through the
//! exported `px_ptr` / `py_ptr` arrays — zero-copy `Float32Array` views
//! over linear memory. State lives in a fixed-capacity static arena, so
//! the module never allocates and the memory buffer never grows.
//!
//! Model: springs (Hooke) toward a rest length + softened Coulomb
//! repulsion + weak centering + optional pointer repulsion, integrated
//! with heavy velocity damping — an underdamped system that settles
//! smoothly ("fluent") instead of oscillating.

#![allow(static_mut_refs)]

const MAX_NODES: usize = 64;
const MAX_EDGES: usize = 160;

const W: f32 = 900.0;
const H: f32 = 520.0;
const CX: f32 = W / 2.0;
const CY: f32 = H / 2.0;

const REST: f32 = 150.0;
const SPRING: f32 = 4.0;
const REPEL: f32 = 90000.0;
const CENTER: f32 = 0.35;
const MOUSE_R: f32 = 130.0;
const MOUSE_F: f32 = 2600.0;
const DAMP: f32 = 0.86;
const MARGIN: f32 = 28.0;

struct Sim {
    n: usize,
    m: usize,
    px: [f32; MAX_NODES],
    py: [f32; MAX_NODES],
    vx: [f32; MAX_NODES],
    vy: [f32; MAX_NODES],
    ea: [u32; MAX_EDGES],
    eb: [u32; MAX_EDGES],
    mx: f32,
    my: f32,
    mouse: bool,
    grabbed: i32,
    t: f32,
}

static mut SIM: Sim = Sim {
    n: 0,
    m: 0,
    px: [0.0; MAX_NODES],
    py: [0.0; MAX_NODES],
    vx: [0.0; MAX_NODES],
    vy: [0.0; MAX_NODES],
    ea: [0; MAX_EDGES],
    eb: [0; MAX_EDGES],
    mx: 0.0,
    my: 0.0,
    mouse: false,
    grabbed: -1,
    t: 0.0,
};

/// Gentle idle "breathing" so the panel never freezes after settling: a
/// small per-node sinusoidal drift (deterministic, phase-offset per node).
const BREEZE: f32 = 14.0;
const BREEZE_W: f32 = 0.7;

/// Place `nodes` nodes on a circle around the panel center and reset the
/// system. Capacities clamp silently at MAX_NODES / MAX_EDGES.
#[no_mangle]
pub extern "C" fn configure(nodes: usize, edges: usize) {
    let n = nodes.min(MAX_NODES);
    let m = edges.min(MAX_EDGES);
    unsafe {
        SIM.n = n;
        SIM.m = m;
        for i in 0..n {
            let a = i as f32 * (std::f32::consts::TAU / n.max(1) as f32);
            SIM.px[i] = CX + a.cos() * 190.0;
            SIM.py[i] = CY + a.sin() * 150.0;
            SIM.vx[i] = 0.0;
            SIM.vy[i] = 0.0;
        }
        for k in 0..m {
            SIM.ea[k] = 0;
            SIM.eb[k] = 0;
        }
    }
}

/// Register spring `k` between node indices `a` and `b`.
#[no_mangle]
pub extern "C" fn set_edge(k: usize, a: u32, b: u32) {
    unsafe {
        if k < SIM.m {
            SIM.ea[k] = a;
            SIM.eb[k] = b;
        }
    }
}

/// Pointer position in stage coordinates; `active != 0` enables the
/// repulsion well around it.
#[no_mangle]
pub extern "C" fn set_mouse(x: f32, y: f32, active: u32) {
    unsafe {
        SIM.mx = x;
        SIM.my = y;
        SIM.mouse = active != 0;
    }
}

/// Pin node `i` to the pointer until `release` (drag interaction). The
/// node's velocity is zeroed and its position follows the pointer every
/// step; neighbours react through the springs.
#[no_mangle]
pub extern "C" fn grab(i: u32) {
    unsafe {
        if (i as usize) < SIM.n {
            SIM.grabbed = i as i32;
        }
    }
}

/// End the drag; the released node keeps its pointer-imparted position and
/// the springs pull the graph back into shape.
#[no_mangle]
pub extern "C" fn release() {
    unsafe {
        SIM.grabbed = -1;
    }
}

/// Advance the simulation by `dt` seconds (clamped to a sane range).
#[no_mangle]
pub extern "C" fn step(dt: f32) {
    let dt = dt.clamp(0.001, 0.033);
    unsafe {
        let n = SIM.n;
        // Repulsion + centering + pointer well → velocity.
        for i in 0..n {
            let mut fx = 0.0;
            let mut fy = 0.0;
            for j in 0..n {
                if i == j {
                    continue;
                }
                let dx = SIM.px[i] - SIM.px[j];
                let dy = SIM.py[i] - SIM.py[j];
                let d2 = dx * dx + dy * dy + 40.0;
                let d = d2.sqrt();
                let mag = REPEL / d2;
                fx += dx / d * mag;
                fy += dy / d * mag;
            }
            fx += (CX - SIM.px[i]) * CENTER;
            fy += (CY - SIM.py[i]) * CENTER;
            // idle drift (skipped while a drag is active — the user is in control)
            if SIM.grabbed < 0 {
                let ph = i as f32 * 1.7;
                fx += (SIM.t * BREEZE_W + ph).cos() * BREEZE;
                fy += (SIM.t * BREEZE_W * 1.3 + ph).sin() * BREEZE;
            }
            if SIM.mouse {
                let dx = SIM.px[i] - SIM.mx;
                let dy = SIM.py[i] - SIM.my;
                let d = (dx * dx + dy * dy).sqrt();
                if d < MOUSE_R {
                    let s = if d < 1.0 { 1.0 } else { d };
                    let mag = MOUSE_F * (MOUSE_R - s) / MOUSE_R;
                    fx += dx / s * mag;
                    fy += dy / s * mag;
                }
            }
            SIM.vx[i] += fx * dt;
            SIM.vy[i] += fy * dt;
        }
        // Springs: symmetric impulses into both endpoints.
        for k in 0..SIM.m {
            let a = SIM.ea[k] as usize;
            let b = SIM.eb[k] as usize;
            if a >= n || b >= n {
                continue;
            }
            let dx = SIM.px[b] - SIM.px[a];
            let dy = SIM.py[b] - SIM.py[a];
            let d = (dx * dx + dy * dy).sqrt().max(1.0);
            let f = SPRING * (d - REST);
            let ux = dx / d * f * dt;
            let uy = dy / d * f * dt;
            SIM.vx[a] += ux;
            SIM.vy[a] += uy;
            SIM.vx[b] -= ux;
            SIM.vy[b] -= uy;
        }
        // Damped integration + stage bounds.
        for i in 0..n {
            SIM.vx[i] *= DAMP;
            SIM.vy[i] *= DAMP;
            if SIM.grabbed == i as i32 {
                // dragged node: pin to the pointer, no residual velocity
                SIM.px[i] = SIM.mx.clamp(MARGIN, W - MARGIN);
                SIM.py[i] = SIM.my.clamp(MARGIN, H - MARGIN);
                SIM.vx[i] = 0.0;
                SIM.vy[i] = 0.0;
            } else {
                SIM.px[i] = (SIM.px[i] + SIM.vx[i]).clamp(MARGIN, W - MARGIN);
                SIM.py[i] = (SIM.py[i] + SIM.vy[i]).clamp(MARGIN, H - MARGIN);
            }
        }
        SIM.t += dt;
    }
}

/// Number of active nodes (capacity-clamped).
#[no_mangle]
pub extern "C" fn node_count() -> usize {
    unsafe { SIM.n }
}

/// Pointer to the live `[f32; node_count()]` X positions in linear memory.
#[no_mangle]
pub extern "C" fn px_ptr() -> *const f32 {
    unsafe { SIM.px.as_ptr() }
}

/// Pointer to the live `[f32; node_count()]` Y positions in linear memory.
#[no_mangle]
pub extern "C" fn py_ptr() -> *const f32 {
    unsafe { SIM.py.as_ptr() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    // SIM is one global; tests must not interleave.
    static LOCK: Mutex<()> = Mutex::new(());

    fn sim() -> &'static mut Sim {
        unsafe { &mut *std::ptr::addr_of_mut!(SIM) }
    }

    fn step_n(frames: usize) {
        for _ in 0..frames {
            step(0.016);
        }
    }

    #[test]
    fn configure_places_nodes_and_resets_state() {
        let _g = LOCK.lock().unwrap();
        configure(3, 2);
        assert_eq!(node_count(), 3);
        let s = sim();
        for i in 0..3 {
            assert!((MARGIN..=W - MARGIN).contains(&s.px[i]));
            assert!((MARGIN..=H - MARGIN).contains(&s.py[i]));
            assert_eq!(s.vx[i], 0.0);
            assert_eq!(s.vy[i], 0.0);
        }
        // reconfigure with fewer nodes clears velocities of the survivors
        step_n(10);
        configure(1, 0);
        let s = sim();
        assert_eq!(node_count(), 1);
        assert_eq!(s.vx[0], 0.0);
    }

    #[test]
    fn capacities_clamp_silently() {
        let _g = LOCK.lock().unwrap();
        configure(MAX_NODES + 10, MAX_EDGES + 10);
        assert_eq!(node_count(), MAX_NODES);
        let s = sim();
        assert_eq!(s.m, MAX_EDGES);
    }

    #[test]
    fn positions_settle_toward_the_center() {
        let _g = LOCK.lock().unwrap();
        configure(6, 5);
        for k in 0..5 {
            set_edge(k, k as u32, (k + 1) as u32);
        }
        let dist = |s: &Sim| -> f32 {
            (0..s.n)
                .map(|i| (s.px[i] - CX).hypot(s.py[i] - CY))
                .sum::<f32>()
                / s.n as f32
        };
        let s = sim();
        let before = dist(s);
        step_n(240);
        let after = dist(sim());
        assert!(
            after < before,
            "mean distance to center should shrink: {before} -> {after}"
        );
    }

    #[test]
    fn grabbed_node_is_pinned_to_the_pointer_and_released_moves() {
        let _g = LOCK.lock().unwrap();
        configure(3, 2);
        set_edge(0, 0, 1);
        set_edge(1, 1, 2);
        step_n(30);
        grab(1);
        set_mouse(120.0, 90.0, 1);
        step_n(5);
        {
            let s = sim();
            assert_eq!(s.grabbed, 1);
            assert!((s.px[1] - 120.0).abs() < 0.001, "pinned x");
            assert!((s.py[1] - 90.0).abs() < 0.001, "pinned y");
            assert_eq!(s.vx[1], 0.0);
            assert_eq!(s.vy[1], 0.0);
        }
        // pointer outside the stage: the pin clamps to the margin
        set_mouse(-500.0, -500.0, 1);
        step_n(2);
        {
            let s = sim();
            assert_eq!(s.px[1], MARGIN);
            assert_eq!(s.py[1], MARGIN);
        }
        release();
        let p0 = { let s = sim(); (s.px[1], s.py[1]) };
        step_n(20);
        let s = sim();
        assert_eq!(s.grabbed, -1);
        assert!((s.px[1] - p0.0).abs() > 0.5, "springs move the node back");
    }

    #[test]
    fn grab_of_out_of_range_index_is_ignored() {
        let _g = LOCK.lock().unwrap();
        configure(2, 0);
        grab(9);
        assert_eq!(sim().grabbed, -1);
    }

    #[test]
    fn pointer_repels_nearby_nodes() {
        let _g = LOCK.lock().unwrap();
        configure(1, 0);
        step_n(60); // settle first
        set_mouse(sim().px[0], sim().py[0], 1);
        let before = sim().px[0];
        step_n(30);
        let s = sim();
        assert!((s.px[0] - before).abs() > 0.5, "pointer well should push the node");
        assert!(s.mouse);
        set_mouse(0.0, 0.0, 0);
        assert!(!sim().mouse);
    }

    #[test]
    fn breeze_keeps_the_system_moving_after_settling() {
        let _g = LOCK.lock().unwrap();
        configure(4, 3);
        step_n(240); // well past settling
        let a = { let s = sim(); (s.px[0], s.py[0]) };
        step_n(90);
        let s = sim();
        assert!((s.px[0] - a.0).abs() + (s.py[0] - a.1).abs() > 0.1, "idle drift must not vanish");
    }

    #[test]
    fn ptrs_expose_live_memory() {
        let _g = LOCK.lock().unwrap();
        configure(3, 0);
        step_n(1);
        let s = sim();
        let xs = unsafe { std::slice::from_raw_parts(px_ptr(), node_count()) };
        let ys = unsafe { std::slice::from_raw_parts(py_ptr(), node_count()) };
        for i in 0..s.n {
            assert_eq!(xs[i], s.px[i]);
            assert_eq!(ys[i], s.py[i]);
        }
    }
}
