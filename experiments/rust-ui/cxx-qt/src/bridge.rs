//! The Rust <-> QML bridge: one QObject, `RingBridge`, registered as a QML
//! type (`#[qml_element]`) in `com.mirql.ring`. QML instantiates it
//! (`RingBridge { id: bridge }` in qml/Ring.qml) and binds the window's
//! `visible` and LayerShellQt properties to it; Rust's `initialize()`
//! (the `cxx_qt::Initialize` trait) spawns the Unix-socket accept thread,
//! handing it a `CxxQtThread` (`cxx_qt::Threading`) so it can post
//! `show`/`hide` back onto the Qt thread.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(bool, visible)]
        type RingBridge = super::RingBridgeRust;

        /// Called from QML's `onFrameSwapped`, once, right after a `show`
        /// takes effect: the closest thing to a "first frame" timestamp
        /// cxx-qt + QQuickWindow gives us without more C++ glue than this
        /// spike's budget allows.
        #[qinvokable]
        fn ack_shown(self: Pin<&mut RingBridge>);
    }

    impl cxx_qt::Threading for RingBridge {}
    impl cxx_qt::Initialize for RingBridge {}
}

use core::pin::Pin;
use cxx_qt::Threading;
use std::sync::atomic::Ordering;

#[derive(Default)]
pub struct RingBridgeRust {
    visible: bool,
}

impl cxx_qt::Initialize for qobject::RingBridge {
    fn initialize(self: Pin<&mut Self>) {
        eprintln!("ring-cxxqt: RingBridge::initialize() called");
        let qt_thread = self.qt_thread();
        std::thread::spawn(move || crate::accept_loop(qt_thread));
    }
}

impl qobject::RingBridge {
    pub fn ack_shown(self: Pin<&mut Self>) {
        let shared = crate::shared();
        let gen = shared.generation.load(Ordering::SeqCst);
        shared.ack_nanos.store(crate::now_nanos(), Ordering::SeqCst);
        shared.ack_generation.store(gen, Ordering::SeqCst);
    }
}
