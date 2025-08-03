from pathlib import Path
import shutil

def init(folder_name):
    OUTPUT_DIR = Path(folder_name)

    if OUTPUT_DIR.exists() and OUTPUT_DIR.is_dir():
        shutil.rmtree(OUTPUT_DIR)

    OUTPUT_DIR.mkdir(exist_ok=True)

    print(f"Cleaned and recreated: {OUTPUT_DIR}")


if __name__ == "__main__":
    init("data")
    init("csv")