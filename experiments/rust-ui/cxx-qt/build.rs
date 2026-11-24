use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(QmlModule::new("com.mirql.ring").qml_files(["qml/Ring.qml"]))
        .files(["src/bridge.rs"])
        .build();
}
