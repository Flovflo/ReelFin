import yaml
import sys

with open('project.yml', 'r') as f:
    config = yaml.safe_load(f)

# Add tvOS target info
config['options']['deploymentTarget']['tvOS'] = "26.0"
config['settings']['base']['TVOS_DEPLOYMENT_TARGET'] = 26.0
config['settings']['base']['TARGETED_DEVICE_FAMILY'] = "1,2,3"

targets = list(config['targets'].keys())
new_targets = {}

for name, orig_target in config['targets'].items():
    # iOS Target
    ios_target = yaml.safe_load(yaml.dump(orig_target))
    ios_target['platform'] = "iOS"
    
    # tvOS Target
    tvos_target = yaml.safe_load(yaml.dump(orig_target))
    tvos_target['platform'] = "tvOS"
    
    # Update tvOS Settings that shouldn't conflict
    if 'settings' not in tvos_target:
        tvos_target['settings'] = {'base': {}}
    if 'base' not in tvos_target['settings']:
        tvos_target['settings']['base'] = {}
        
    # Update bundle ID for tvOS (optional, Apple recommends same bundle ID for Universal Purchase)
    # We will keep the same bundle ID so they match
    
    # Update dependencies
    if 'dependencies' in ios_target:
        new_deps_ios = []
        new_deps_tvos = []
        for dep in ios_target['dependencies']:
            if 'target' in dep and dep['target'] in targets:
                # Local target
                new_deps_ios.append({'target': dep['target'] + "_iOS"})
                new_deps_tvos.append({'target': dep['target'] + "_tvOS"})
            else:
                # 3rd party package or framework (e.g. GRDB)
                new_deps_ios.append(dep)
                new_deps_tvos.append(dep)
        ios_target['dependencies'] = new_deps_ios
        tvos_target['dependencies'] = new_deps_tvos
        
    new_targets[f"{name}_iOS"] = ios_target
    new_targets[f"{name}_tvOS"] = tvos_target

config['targets'] = new_targets

# Update Schemes
new_schemes = {}
for name, scheme in config['schemes'].items():
    new_scheme = yaml.safe_load(yaml.dump(scheme))
    
    # Build targets
    if 'build' in new_scheme and 'targets' in new_scheme['build']:
        build_targets = {}
        for b_name, b_val in new_scheme['build']['targets'].items():
            if b_name in targets:
                build_targets[f"{b_name}_iOS"] = b_val
                build_targets[f"{b_name}_tvOS"] = b_val
            else:
                build_targets[b_name] = b_val
        new_scheme['build']['targets'] = build_targets
        
    # Test targets
    if 'test' in new_scheme and 'targets' in new_scheme['test']:
        test_targets = []
        for t_name in new_scheme['test']['targets']:
            if t_name in targets:
                test_targets.append(f"{t_name}_iOS")
                test_targets.append(f"{t_name}_tvOS")
            else:
                test_targets.append(t_name)
        new_scheme['test']['targets'] = test_targets
        
    new_schemes[name] = new_scheme

config['schemes'] = new_schemes

with open('project.yml', 'w') as f:
    yaml.dump(config, f, sort_keys=False)

print("project.yml updated.")
