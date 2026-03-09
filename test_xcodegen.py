import yaml
with open('project.yml', 'r') as f:
    data = yaml.safe_load(f)

print("Parsed YAML.")
