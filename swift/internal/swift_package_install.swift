// Copyright 2018 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

struct Dependency: Codable {
  var name: String
  var url: String
  var version: String
  var path: String
  var dependencies: [Dependency]?
}
// Current directory 
let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

// Current repository name
let repositoryName = CommandLine.arguments[1]
// Swift executable path that provided by bazel
let swiftPath = CommandLine.arguments[2]
let arPath = CommandLine.arguments[3]
// Build path where swift package manager puts all the artifacts
let buildPath = URL(fileURLWithPath: CommandLine.arguments[4], relativeTo: cwd)

let depgraphPath = URL(fileURLWithPath: "./depgraph.json", relativeTo: cwd);

let depgraphJson = try String(contentsOf: depgraphPath, encoding: .utf8).data(using: .utf8)
let dependencyGraph = try JSONDecoder().decode(Dependency.self, from: depgraphJson!)

func generateBuildFile(_ dependency: Dependency) throws -> Void {
  print("Generating BUILD.bazel for \(dependency.name)")
  let dependencies = dependency.dependencies!.map { "\"@\(repositoryName)//\($0.name)\"" }
  let buildfileContent = 
    """
    # This file is automatically generated by swift_package_install rule please do not edit.
    # All rules in other repositories can use this target
    # Generated for \(dependency.name)@\(dependency.version)
    # Url: \(dependency.url)

    package(default_visibility = ["//visibility:public"])
    load("@build_bazel_rules_swift//swift:swift.bzl", "swift_import")

    swift_import(
      name = "\(dependency.name)",
      archives = [
        ":\(dependency.name).a",
      ],
      swiftmodules = [
        ":\(dependency.name).swiftmodule",
      ],
      swiftdocs = [
        ":\(dependency.name).swiftdoc",
      ],
      deps = [
        \(dependencies.joined(separator: ",\n"))
      ]
    )
    """

  let buildFilePath = URL(fileURLWithPath: "\(dependency.name)/BUILD.bazel", relativeTo: cwd);
  try buildfileContent.write(to: buildFilePath, atomically: true, encoding: .utf8);

  for dependency in dependency.dependencies! {
    try generateBuildFile(dependency)
  }
}

func createModule(_ dependency: Dependency) throws -> Void {
  let dependencyPath = URL(fileURLWithPath: dependency.name, relativeTo: cwd);
  try FileManager.default.createDirectory(atPath: dependencyPath.path, withIntermediateDirectories: true, attributes: nil)


  try FileManager.default.copyItem(
    atPath: "\(buildPath.path)/\(dependency.name).swiftmodule", 
    toPath: "\(dependencyPath.path)/\(dependency.name).swiftmodule"
  )

  try FileManager.default.copyItem(
    atPath: "\(buildPath.path)/\(dependency.name).swiftdoc", 
    toPath: "\(dependencyPath.path)/\(dependency.name).swiftdoc"
  )

  var args = ["rcs", "\(dependencyPath.path)/\(dependency.name).a"];

  let allFiles = FileManager.default.enumerator(atPath: "\(buildPath.path)/\(dependency.name).build")
  let objectFiles = (allFiles?.allObjects as! [String])
      .filter{$0.hasSuffix(".o")}
      .map{"\(buildPath.path)/\(dependency.name).build/\($0)"}
  
  args += objectFiles

  let proc = Process()
  proc.executableURL = URL(fileURLWithPath: arPath)
  proc.arguments = args
  try proc.run()
  proc.waitUntilExit()

  for dependency in dependency.dependencies! {
    try createModule(dependency)
  }
}

func buildPackage(_ dependency: Dependency) throws -> Void {
  let proc = Process()
  proc.executableURL = URL(fileURLWithPath: swiftPath)
  proc.arguments = ["build", "-c", "release", "--target", dependency.name]
  try proc.run()
  proc.waitUntilExit()
}

for dependency in dependencyGraph.dependencies! {
  print("Building \(dependency.name)")
  try buildPackage(dependency)
  try createModule(dependency)
  try generateBuildFile(dependency)
}
