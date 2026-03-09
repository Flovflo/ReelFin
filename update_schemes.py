import yaml
with open('project.yml', 'r') as f:
    config = yaml.safe_load(f)

old_scheme = config['schemes']['ReelFin']
ios_scheme = {
    'build': {'targets': {'ReelFinApp_iOS': 'all', 'ReelFinWidgetsExtension_iOS': 'all'}},
    'test': {'targets': [t for t in old_scheme['test']['targets'] if '_iOS' in t]}
}
tvos_scheme = {
    'build': {'targets': {'ReelFinApp_tvOS': 'all', 'ReelFinWidgetsExtension_tvOS': 'all'}},
    'test': {'targets': [t for t in old_scheme['test']['targets'] if '_tvOS' in t]}
}

config['schemes'] = {'ReelFin': ios_scheme, 'ReelFin_tvOS': tvos_scheme}

with open('project.yml', 'w') as f:
    yaml.dump(config, f, sort_keys=False)
