#!/usr/bin/env python3

import logging
import os
import subprocess

from flask import Flask, request, jsonify, render_template_string
from werkzeug.utils import secure_filename

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 50 * 1024 * 1024  # 50MB max file size

# Configuration
UPLOAD_FOLDER = '/app/uploads'
ALLOWED_EXTENSIONS = {'mcaddon'}
MINECRAFT_DATA_DIR = '/root/tools/minecraft'

# Ensure upload directory exists
os.makedirs(UPLOAD_FOLDER, exist_ok=True)


def extract_entity_identifiers(resource_dir):
    """Extract all entity identifiers from resource pack"""
    identifiers = []
    entity_dir = os.path.join(resource_dir, 'entity')

    if not os.path.exists(entity_dir):
        return identifiers

    try:
        for filename in os.listdir(entity_dir):
            if filename.endswith('.json'):
                filepath = os.path.join(entity_dir, filename)
                try:
                    with open(filepath, 'r') as f:
                        content = f.read()

                    # Use jq to extract identifier (more reliable than Python JSON for malformed files)
                    result = subprocess.run(
                        ['jq', '-r', '''
                        (."minecraft:entity"?.description.identifier) //
                        (."minecraft:client_entity"?.description.identifier) //
                        empty
                        '''],
                        input=content,
                        text=True,
                        capture_output=True
                    )

                    if result.returncode == 0 and result.stdout.strip():
                        identifier = result.stdout.strip()
                        if identifier and identifier != 'null':
                            identifiers.append(identifier)

                except Exception as e:
                    logger.warning(f"Could not parse entity file {filename}: {e}")

    except Exception as e:
        logger.error(f"Error scanning entity directory: {e}")

    return identifiers


def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def run_shell_script(script_path, *args):
    """Run a shell script and return the result"""
    try:
        cmd = [script_path] + list(args)
        logger.info(f"Running command: {' '.join(cmd)}")

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=False,
            timeout=300  # 5 minute timeout
        )

        return {
            'success': result.returncode == 0,
            'returncode': result.returncode,
            'stdout': result.stdout,
            'stderr': result.stderr
        }
    except subprocess.TimeoutExpired:
        return {
            'success': False,
            'returncode': -1,
            'stdout': '',
            'stderr': 'Command timed out after 5 minutes'
        }
    except Exception as e:
        return {
            'success': False,
            'returncode': -1,
            'stdout': '',
            'stderr': str(e)
        }


# HTML template for the upload form
UPLOAD_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Minecraft Addon Manager</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; margin-bottom: 30px; }
        .upload-section { border: 2px dashed #3498db; padding: 30px; text-align: center; margin: 20px 0; border-radius: 8px; }
        .upload-section:hover { border-color: #2980b9; background-color: #f8f9fa; }
        input[type="file"] { margin: 20px 0; }
        button { background-color: #3498db; color: white; padding: 12px 30px; border: none; border-radius: 4px; cursor: pointer; font-size: 16px; }
        button:hover { background-color: #2980b9; }
        button:disabled { background-color: #bdc3c7; cursor: not-allowed; }
        .result { margin-top: 20px; padding: 15px; border-radius: 4px; }
        .success { background-color: #d4edda; border: 1px solid #c3e6cb; color: #155724; }
        .error { background-color: #f8d7da; border: 1px solid #f5c6cb; color: #721c24; }
        .loading { display: none; color: #6c757d; }
        pre { background-color: #f8f9fa; padding: 10px; border-radius: 4px; overflow-x: auto; white-space: pre-wrap; }
        .actions { display: flex; gap: 10px; margin: 20px 0; }
        .info { background-color: #d1ecf1; border: 1px solid #bee5eb; color: #0c5460; padding: 15px; border-radius: 4px; margin-bottom: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎮 Minecraft Addon Manager</h1>

        <div class="info">
            <strong>📝 Instructions:</strong><br>
            • Upload .mcaddon files to install custom entities, behaviors, and resources<br>
            • Files are automatically installed and the Minecraft server is restarted<br>
            • Use the remove endpoint to clean up old addons
        </div>

        <div class="upload-section">
            <h3>📦 Upload Addon</h3>
            <form id="uploadForm" enctype="multipart/form-data">
                <input type="file" id="fileInput" name="file" accept=".mcaddon" required>
                <br>
                <button type="submit">Install Addon</button>
            </form>
            <div id="loading" class="loading">⏳ Installing addon... This may take a few minutes.</div>
        </div>

        <div class="actions">
            <button onclick="listAddons()">📋 List Installed Addons</button>
            <button onclick="showRemoveForm()">🗑️ Remove Addons</button>
        </div>

        <div id="result"></div>
    </div>

    <script>
        document.getElementById('uploadForm').addEventListener('submit', async function(e) {
            e.preventDefault();

            const fileInput = document.getElementById('fileInput');
            const loadingDiv = document.getElementById('loading');
            const resultDiv = document.getElementById('result');
            const submitButton = e.target.querySelector('button[type="submit"]');

            if (!fileInput.files[0]) {
                alert('Please select a file first.');
                return;
            }

            const formData = new FormData();
            formData.append('file', fileInput.files[0]);

            loadingDiv.style.display = 'block';
            submitButton.disabled = true;
            resultDiv.innerHTML = '';

            try {
                const response = await fetch('/api/install', {
                    method: 'POST',
                    body: formData
                });

                const result = await response.json();

                if (result.success) {
                    let entityInfoHtml = '';
                    if (result.entity_info) {
                        if (result.entity_count > 1) {
                            entityInfoHtml = '<br><strong>Entities (' + result.entity_count + '):</strong><br><pre>' + result.entity_info + '</pre>';
                        } else {
                            entityInfoHtml = '<br><strong>Entity:</strong> ' + result.entity_info;
                        }
                    }

                    resultDiv.innerHTML = '<div class="result success"><strong>✅ Success!</strong><br>' + 
                        result.message + entityInfoHtml + 
                        '<br><br><strong>Installation Log:</strong><pre>' + result.output + '</pre></div>';
                } else {
                    resultDiv.innerHTML = '<div class="result error"><strong>❌ Error:</strong> ' + 
                        result.message + '<br><pre>' + result.error + '</pre></div>';
                }
            } catch (error) {
                resultDiv.innerHTML = '<div class="result error"><strong>❌ Network Error:</strong> ' + 
                    error.message + '</div>';
            } finally {
                loadingDiv.style.display = 'none';
                submitButton.disabled = false;
                fileInput.value = '';
            }
        });

        async function listAddons() {
            const resultDiv = document.getElementById('result');
            resultDiv.innerHTML = '<div class="loading">📋 Loading addon list...</div>';

            try {
                const response = await fetch('/api/list');
                const result = await response.json();

                if (result.success) {
                    let output = result.output || 'No custom addons found.';
                    if (output.trim() === '') {
                        output = 'No custom addons installed.';
                    }
                    resultDiv.innerHTML = '<div class="result success"><strong>📦 Installed Addons:</strong><br><pre>' + 
                        output + '</pre></div>';
                } else {
                    resultDiv.innerHTML = '<div class="result error"><strong>❌ Error:</strong> ' + 
                        result.message + '</div>';
                }
            } catch (error) {
                resultDiv.innerHTML = '<div class="result error"><strong>❌ Network Error:</strong> ' + 
                    error.message + '</div>';
            }
        }

        async function showRemoveForm() {
            const resultDiv = document.getElementById('result');
            resultDiv.innerHTML = '<div class="loading">📋 Loading installed addons...</div>';

            try {
                const response = await fetch('/api/list');
                const result = await response.json();

                if (result.success) {
                    const addons = parseAddonList(result.output);

                    if (addons.length === 0) {
                        resultDiv.innerHTML = '<div class="result"><strong>📦 No Addons Found</strong><br>No custom addons are currently installed.</div>';
                        return;
                    }

                    let addonCheckboxes = addons.map(function(addon, index) {
                        return '<div style="margin: 10px 0; padding: 10px; border: 1px solid #ddd; border-radius: 4px;">' +
                            '<label style="display: flex; align-items: center; cursor: pointer;">' +
                            '<input type="checkbox" name="addon" value="' + addon.name + '" style="margin-right: 10px; transform: scale(1.2);">' +
                            '<div><strong>' + addon.name + '</strong>' +
                            (addon.details ? '<br><small style="color: #666;">' + addon.details + '</small>' : '') +
                            '</div></label></div>';
                    }).join('');

                    resultDiv.innerHTML = '<div class="result">' +
                        '<strong>🗑️ Remove Addons</strong><br><br>' +
                        '<form id="removeForm">' +
                        '<div style="margin-bottom: 20px;">' +
                        '<label style="display: flex; align-items: center; margin-bottom: 15px; cursor: pointer;">' +
                        '<input type="checkbox" id="selectAll" style="margin-right: 10px; transform: scale(1.2);">' +
                        '<strong>Select All</strong></label></div>' +
                        '<div style="max-height: 300px; overflow-y: auto; border: 1px solid #ddd; padding: 10px; border-radius: 4px; margin-bottom: 20px;">' +
                        addonCheckboxes + '</div>' +
                        '<div style="display: flex; gap: 10px; margin-top: 20px;">' +
                        '<button type="submit" style="background-color: #dc3545; border-color: #dc3545;">🗑️ Remove Selected</button>' +
                        '<button type="button" onclick="removeAllAddons()" style="background-color: #6c757d; border-color: #6c757d;">🗑️ Remove All</button>' +
                        '<button type="button" onclick="hideRemoveForm()" style="background-color: #6c757d; border-color: #6c757d;">❌ Cancel</button>' +
                        '</div></form>' +
                        '<div id="removeResult" style="margin-top: 20px;"></div></div>';

                    setupRemoveFormListeners();
                } else {
                    resultDiv.innerHTML = '<div class="result error"><strong>❌ Error loading addons:</strong> ' + 
                        result.message + '</div>';
                }
            } catch (error) {
                resultDiv.innerHTML = '<div class="result error"><strong>❌ Network Error:</strong> ' + 
                    error.message + '</div>';
            }
        }

        function parseAddonList(output) {
            const addons = [];
            const lines = output.split('\\n');
            let currentSection = '';

            for (const line of lines) {
                if (line.includes('=== Behavior Packs ===')) {
                    currentSection = 'behavior';
                    continue;
                } else if (line.includes('=== Resource Packs ===')) {
                    currentSection = 'resource';
                    continue;
                }

                const match = line.match(/^\\s*-\\s*([^\\s(]+)(\\s*\\(.*\\))?/);
                if (match) {
                    const name = match[1];
                    const details = match[2] ? match[2].trim() : '';

                    if (!addons.find(function(addon) { return addon.name === name; })) {
                        addons.push({
                            name: name,
                            details: details,
                            section: currentSection
                        });
                    }
                }
            }

            return addons;
        }

        function setupRemoveFormListeners() {
            const selectAllCheckbox = document.getElementById('selectAll');
            const addonCheckboxes = document.querySelectorAll('input[name="addon"]');
            const removeForm = document.getElementById('removeForm');

            selectAllCheckbox.addEventListener('change', function() {
                addonCheckboxes.forEach(function(checkbox) {
                    checkbox.checked = selectAllCheckbox.checked;
                });
            });

            addonCheckboxes.forEach(function(checkbox) {
                checkbox.addEventListener('change', function() {
                    const allChecked = Array.from(addonCheckboxes).every(function(cb) { return cb.checked; });
                    const noneChecked = Array.from(addonCheckboxes).every(function(cb) { return !cb.checked; });

                    selectAllCheckbox.checked = allChecked;
                    selectAllCheckbox.indeterminate = !allChecked && !noneChecked;
                });
            });

            removeForm.addEventListener('submit', async function(e) {
                e.preventDefault();
                await removeSelectedAddons();
            });
        }

        async function removeSelectedAddons() {
            const selectedAddons = Array.from(document.querySelectorAll('input[name="addon"]:checked'))
                .map(function(checkbox) { return checkbox.value; });

            if (selectedAddons.length === 0) {
                alert('Please select at least one addon to remove.');
                return;
            }

            if (!confirm('Are you sure you want to remove ' + selectedAddons.length + ' addon(s)?\\n\\n' + 
                selectedAddons.join(', ') + '\\n\\nThis action cannot be undone.')) {
                return;
            }

            await performRemoval({ packs: selectedAddons, confirm: true });
        }

        async function removeAllAddons() {
            if (!confirm('Are you sure you want to remove ALL custom addons?\\n\\nThis will remove all custom behavior and resource packs.\\nThis action cannot be undone.')) {
                return;
            }

            await performRemoval({ remove_all: true, confirm: true });
        }

        async function performRemoval(payload) {
            const removeResult = document.getElementById('removeResult');
            const submitButton = document.querySelector('#removeForm button[type="submit"]');

            removeResult.innerHTML = '<div class="loading">🗑️ Removing addons... This may take a few minutes.</div>';
            if (submitButton) submitButton.disabled = true;

            try {
                const response = await fetch('/api/remove', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(payload)
                });

                const result = await response.json();

                if (result.success) {
                    removeResult.innerHTML = '<div class="result success"><strong>✅ Success!</strong><br>' +
                        result.message + '<br><br><strong>Removal Log:</strong><pre>' + result.output + '</pre></div>';

                    setTimeout(function() {
                        showRemoveForm();
                    }, 3000);
                } else {
                    removeResult.innerHTML = '<div class="result error"><strong>❌ Error:</strong> ' +
                        result.message + '<br><pre>' + (result.error || '') + '</pre></div>';
                }
            } catch (error) {
                removeResult.innerHTML = '<div class="result error"><strong>❌ Network Error:</strong> ' +
                    error.message + '</div>';
            } finally {
                if (submitButton) submitButton.disabled = false;
            }
        }

        function hideRemoveForm() {
            document.getElementById('result').innerHTML = '';
        }
    </script>
</body>
</html>
"""


@app.route('/')
def index():
    """Serve the upload form"""
    return render_template_string(UPLOAD_TEMPLATE)


@app.route('/api/install', methods=['POST'])
def install_addon():
    """Install a .mcaddon file"""
    try:
        # Check if file was uploaded
        if 'file' not in request.files:
            return jsonify({'success': False, 'message': 'No file uploaded'}), 400

        file = request.files['file']
        if file.filename == '':
            return jsonify({'success': False, 'message': 'No file selected'}), 400

        if not allowed_file(file.filename):
            return jsonify({'success': False, 'message': 'Invalid file type. Only .mcaddon files are allowed.'}), 400

        # Save uploaded file
        filename = secure_filename(file.filename)
        filepath = os.path.join(UPLOAD_FOLDER, filename)
        file.save(filepath)

        logger.info(f"Saved uploaded file: {filepath}")

        # Get addon name before running the script
        addon_name = os.path.splitext(filename)[0]

        # Run installation script
        result = run_shell_script('./install-mcaddon.sh', filepath)

        # Clean up uploaded file
        try:
            os.remove(filepath)
        except:
            pass

        if result['success']:
            # Extract entity identifiers from the installed resource pack
            entity_identifiers = []
            entity_info = None

            try:
                resource_dir = os.path.join(MINECRAFT_DATA_DIR, 'resource_packs', addon_name)
                entity_identifiers = extract_entity_identifiers(resource_dir)

                # Build entity info string
                if entity_identifiers:
                    if len(entity_identifiers) == 1:
                        entity_info = f"Summon with: /summon {entity_identifiers[0]}"
                    else:
                        entity_info = "Summon commands:\n" + "\n".join([f"/summon {eid}" for eid in entity_identifiers])
            except Exception as e:
                logger.warning(f"Could not extract entity identifiers: {e}")
                entity_identifiers = []
                entity_info = None

            return jsonify({
                'success': True,
                'message': f'Successfully installed {filename}',
                'output': result['stdout'],
                'entity_info': entity_info,
                'entity_count': len(entity_identifiers),
                'entities': entity_identifiers
            })
        else:
            return jsonify({
                'success': False,
                'message': f'Failed to install {filename}',
                'error': result['stderr'] or result['stdout']
            }), 500

    except Exception as e:
        logger.error(f"Error installing addon: {str(e)}")
        return jsonify({
            'success': False,
            'message': 'Internal server error',
            'error': str(e)
        }), 500


@app.route('/api/remove', methods=['POST'])
def remove_addons():
    """Remove installed addons"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'success': False, 'message': 'No JSON data provided'}), 400

        if not data.get('confirm'):
            return jsonify({'success': False, 'message': 'Confirmation required'}), 400

        # Build the removal command
        if data.get('remove_all'):
            # Remove all custom packs
            result = run_shell_script('./remove-mcaddon.sh', 'all')
        elif 'packs' in data and isinstance(data['packs'], list):
            if not data['packs']:
                return jsonify({'success': False, 'message': 'No packs specified for removal'}), 400

            # Remove specific packs by name
            pack_names = ' '.join(f'"{pack}"' for pack in data['packs'])
            result = run_shell_script('./remove-mcaddon.sh', 'selective', pack_names)
        else:
            return jsonify(
                {'success': False, 'message': 'Invalid request format. Use "remove_all": true or "packs": [...]'}), 400

        if result['success']:
            return jsonify({
                'success': True,
                'message': 'Successfully removed addons',
                'output': result['stdout']
            })
        else:
            return jsonify({
                'success': False,
                'message': 'Failed to remove addons',
                'error': result['stderr'] or result['stdout']
            }), 500

    except Exception as e:
        logger.error(f"Error removing addons: {str(e)}")
        return jsonify({
            'success': False,
            'message': 'Internal server error',
            'error': str(e)
        }), 500


@app.route('/api/list', methods=['GET'])
def list_addons():
    """List installed addons"""
    try:
        # Run a simplified version to list packs with entity counts
        result = subprocess.run(
            ['bash', '-c', f'''
            DATA_DIR="{MINECRAFT_DATA_DIR}"
            BEHAVIOR_DIR="$DATA_DIR/behavior_packs"
            RESOURCE_DIR="$DATA_DIR/resource_packs"

            echo "=== Behavior Packs ==="
            if [ -d "$BEHAVIOR_DIR" ]; then
                find "$BEHAVIOR_DIR" -maxdepth 1 -type d -not -path "$BEHAVIOR_DIR" | while read pack; do
                    basename_pack=$(basename "$pack")
                    if [[ ! "$basename_pack" =~ ^(vanilla|chemistry|experimental) ]]; then
                        # Count entities in behavior pack
                        entity_count=0
                        if [ -d "$pack/entities" ]; then
                            entity_count=$(find "$pack/entities" -name "*.json" | wc -l)
                        fi

                        if [ "$entity_count" -gt 0 ]; then
                            echo "  - $basename_pack ($entity_count entities)"
                        else
                            echo "  - $basename_pack"
                        fi
                    fi
                done
            else
                echo "  (No behavior packs directory found)"
            fi

            echo
            echo "=== Resource Packs ==="
            if [ -d "$RESOURCE_DIR" ]; then
                find "$RESOURCE_DIR" -maxdepth 1 -type d -not -path "$RESOURCE_DIR" | while read pack; do
                    basename_pack=$(basename "$pack")
                    if [[ ! "$basename_pack" =~ ^(vanilla|chemistry|editor) ]]; then
                        # Count and list entities in resource pack
                        entity_count=0
                        entity_info=""
                        if [ -d "$pack/entity" ]; then
                            entity_files=$(find "$pack/entity" -name "*.json")
                            entity_count=$(echo "$entity_files" | wc -l)

                            if [ "$entity_count" -gt 0 ]; then
                                echo "  - $basename_pack ($entity_count entities):"
                                echo "$entity_files" | while read entity_file; do
                                    if [ -f "$entity_file" ]; then
                                        identifier=$(jq -r '(."minecraft:entity"?.description.identifier) // (."minecraft:client_entity"?.description.identifier) // empty' "$entity_file" 2>/dev/null)
                                        if [ -n "$identifier" ] && [ "$identifier" != "null" ]; then
                                            echo "      /summon $identifier"
                                        fi
                                    fi
                                done
                            else
                                echo "  - $basename_pack"
                            fi
                        else
                            echo "  - $basename_pack"
                        fi
                    fi
                done
            else
                echo "  (No resource packs directory found)"
            fi
            '''],
            capture_output=True,
            text=True,
            timeout=60
        )

        return jsonify({
            'success': True,
            'output': result.stdout,
            'packs': result.stdout
        })

    except Exception as e:
        logger.error(f"Error listing addons: {str(e)}")
        return jsonify({
            'success': False,
            'message': 'Internal server error',
            'error': str(e)
        }), 500


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy'})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=False)
