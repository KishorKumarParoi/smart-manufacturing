"""
Enterprise Data Platform & Lakehouse Architecture Package.
Features Apache Iceberg / Delta Lake management, streaming vs batch dual-path pipelines, and Feast feature freshness SLAs.
"""

from src.data_platform.lakehouse import LakehouseManager, TableSnapshot, IngestionPath
from src.data_platform.feature_store import IndustrialFeatureStore, FeatureFreshnessReport

__all__ = [
    "LakehouseManager",
    "TableSnapshot",
    "IngestionPath",
    "IndustrialFeatureStore",
    "FeatureFreshnessReport",
]
