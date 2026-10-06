import subprocess


AGENCY_IDS = ["1", "2", "4", "6", "10"]


# get_native_timetables.py e un script nepublicat extrem de lung si muncitoresc care doar incearca url-uri si fallback-uri si scrie csv-uri
def main():
    subprocess.run(
        [
            "python",
            "get_native_timetables.py",
            "--agencies",
            ",".join(AGENCY_IDS),
            "--data-dir",
            "data",
            "--output-dir",
            "csv",
        ],
        check=True,
    )


if __name__ == "__main__":
    main()
