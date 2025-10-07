use std::fs::File;
use std::io::Write;
use std::path::PathBuf;
use std::{env, fs};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_dir = PathBuf::from("proto");
    let proto_files = &["v1/job.proto"];
    let generated_dir = PathBuf::from("./generated/rpc");

    // Ensure the generated directory exists
    if !generated_dir.exists() {
        fs::create_dir_all(&generated_dir)?;
    }

    // Tell Cargo to rerun this script if proto files or build.rs change
    for proto_file in proto_files {
        println!(
            "cargo:rerun-if-changed={}",
            proto_dir.join(proto_file).display()
        );
    }
    println!("cargo:rerun-if-changed=build.rs");

    // Run tonic_build to generate code
    tonic_build::configure()
        .type_attribute(".", "#[derive(serde::Serialize, serde::Deserialize)]")
        .build_client(true)
        .build_server(true)
        .file_descriptor_set_path(
            PathBuf::from(env::var("OUT_DIR").unwrap()).join("zama_job_api_descriptor.bin"),
        )
        .out_dir(&generated_dir)
        .compile_protos(proto_files, &[proto_dir.clone()])?;

    // Generate mod.rs in generated/rpc
    let mod_file_path = generated_dir.join("mod.rs");
    let mut mod_content = String::new();
    for proto_file in proto_files {
        let path = proto_dir.join(proto_file);
        let content = fs::read_to_string(&path)?;

        if let Some(package_line) = content.lines().find(|l| l.trim().starts_with("package")) {
            let package_name = package_line
                .trim()
                .trim_start_matches("package")
                .trim()
                .trim_end_matches(';')
                .trim();
            mod_content.push_str(&format!("pub mod {};\n", package_name));
        }
    }

    // Only write mod.rs if its content has changed
    if fs::read_to_string(&mod_file_path)
        .map(|existing| existing != mod_content)
        .unwrap_or(true)
    {
        let mut mod_file = File::create(&mod_file_path)?;
        mod_file.write_all(mod_content.as_bytes())?;
    }

    // Generate mod.rs in generated directory
    let gen_mod_file_path = PathBuf::from("./src/generated").join("mod.rs");
    let gen_mod_content = "pub mod rpc;\n";
    if fs::read_to_string(&gen_mod_file_path)
        .map(|existing| existing != gen_mod_content)
        .unwrap_or(true)
    {
        let mut gen_mod_file = File::create(&gen_mod_file_path)?;
        gen_mod_file.write_all(gen_mod_content.as_bytes())?;
    }

    Ok(())
}
