. ./scripts/load_azd_env.ps1

. ./scripts/load_python_env.ps1

Start-Process -FilePath $venvPythonPath -ArgumentList "./scripts/setup_search_service.py" -Wait -NoNewWindow
